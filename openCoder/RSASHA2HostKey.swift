import Foundation
import NIO
import NIOSSH
import Security

/// RSA-SHA2 主机密钥支持（RFC 8332：rsa-sha2-256 / rsa-sha2-512）。
///
/// 背景（2026-09-26 真机探针实测）：服务器 OpenSSH 10.0p2 的 KEXINIT 主机密钥
/// 算法只有 `rsa-sha2-512, rsa-sha2-256`。Citadel 的 `SSHAlgorithms.all` 只注册了
/// 旧式 `ssh-rsa`（SHA1 签名，OpenSSH 8.8+ 默认已禁用），fork 本身完全没有
/// RSA-SHA2，导致主机密钥这一项零交集 → keyExchangeNegotiationFailure。
/// 注意 KEX / 加密 / MAC 当时都是有交集的，之前"加密算法缺失"的推断是错的，
/// 真正缺的是 RSA-SHA2 主机密钥算法。
///
/// RFC 8332 的关键点：「签名算法名」和「密钥类型名」是分离的 ——
/// KEXINIT 里广播的是签名算法名（rsa-sha2-256），而服务器发来的主机密钥 blob
/// 里的 key type 永远是 `ssh-rsa`（密钥格式没变）。fork 的架构把这两个名字绑在
/// 同一个 `publicKeyPrefix` 上，所以拆成两类类型：
///   - `RSASSHHostKey`（prefix "ssh-rsa"）：真正解析 blob + 验签；
///   - `RSASHA256AdvertisedKey` / `RSASHA512AdvertisedKey`：只为把签名算法名
///     送进 KEXINIT 广播清单（解析/验签实际走 RSASSHHostKey）。
/// 另外 fork 的 `SSHKeyExchangeStateMachine.handle(keyExchangeReply:)` 里有个
/// guard 强制要求「解析出的密钥类型 == 协商出的算法名」，对 RSA-SHA2 不成立，
/// 已在 Vendor/swift-nio-ssh 里打了最小补丁（见 PATCHES.md）。
///
/// 验签用 Security.framework 的 SecKey（RSA PKCS#1 v1.5 + SHA-256 / SHA-512），
/// 不引入新依赖。

enum RSAHostKeyError: Error {
    case malformedPublicKey
    case malformedSignature
}

// MARK: - 签名类型

/// rsa-sha2-256 签名：wire 上算法名之后就是一串原始 RSA 签名字节（string）。
public struct RSASHA256Signature: NIOSSHSignatureProtocol {
    public static let signaturePrefix = "rsa-sha2-256"
    public let rawRepresentation: Data

    public init(rawRepresentation: Data) {
        self.rawRepresentation = rawRepresentation
    }

    public func write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeSSHString(rawRepresentation)
    }

    public static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let bytes = buffer.readSSHBuffer(),
              let data = bytes.getData(at: 0, length: bytes.readableBytes),
              !data.isEmpty else {
            throw RSAHostKeyError.malformedSignature
        }
        return Self(rawRepresentation: data)
    }
}

/// rsa-sha2-512 签名：同上，只是哈希不同。
public struct RSASHA512Signature: NIOSSHSignatureProtocol {
    public static let signaturePrefix = "rsa-sha2-512"
    public let rawRepresentation: Data

    public init(rawRepresentation: Data) {
        self.rawRepresentation = rawRepresentation
    }

    public func write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeSSHString(rawRepresentation)
    }

    public static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let bytes = buffer.readSSHBuffer(),
              let data = bytes.getData(at: 0, length: bytes.readableBytes),
              !data.isEmpty else {
            throw RSAHostKeyError.malformedSignature
        }
        return Self(rawRepresentation: data)
    }
}

// MARK: - 主机密钥（解析 + 验签）

/// RSA 主机密钥：解析服务器发来的 `ssh-rsa` blob（mpint e, mpint n），
/// 并用 RSA-SHA2 验证 exchange hash 上的签名。
///
/// publicKeyPrefix 必须是 "ssh-rsa"：blob 里的 key type 就是这个名字，
/// NIOSSH 靠它把 blob 路由到本类型。KEXINIT 广播的签名算法名
///（rsa-sha2-256/512）由下面的 AdvertisedKey 类型负责。
public struct RSASSHHostKey: NIOSSHPublicKeyProtocol {
    public static let publicKeyPrefix = "ssh-rsa"

    /// 公钥指数 e（mpint 原始字节，原样保存以便写回）。
    public let exponent: Data
    /// 模数 n（mpint 原始字节，原样保存以便写回）。
    public let modulus: Data

    public init(exponent: Data, modulus: Data) {
        self.exponent = exponent
        self.modulus = modulus
    }

    public var rawRepresentation: Data { exponent + modulus }

    public func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        let sigBytes: Data
        let algorithm: SecKeyAlgorithm
        switch signature {
        case let s as RSASHA256Signature:
            sigBytes = s.rawRepresentation
            algorithm = .rsaSignatureMessagePKCS1v15SHA256
        case let s as RSASHA512Signature:
            sigBytes = s.rawRepresentation
            algorithm = .rsaSignatureMessagePKCS1v15SHA512
        default:
            // 旧式 ssh-rsa（SHA1）签名我们不支持：直接拒绝，不降级。
            return false
        }
        guard let key = RSASecKey.publicKey(modulus: modulus, exponent: exponent) else {
            return false
        }
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(key, algorithm, Data(data) as CFData, sigBytes as CFData, &error)
    }

    public func write(to buffer: inout ByteBuffer) -> Int {
        // e / n 原样写回：SSH 里 mpint 和 string 的编码都是「长度 + 字节」，
        // 原样写回保证 exchange hash 的输入与服务器 blob 字节完全一致，
        // TOFU pin 的字节也保持稳定。
        var written = 0
        written += buffer.writeSSHString(exponent)
        written += buffer.writeSSHString(modulus)
        return written
    }

    public static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let e = buffer.readSSHBuffer(),
              let n = buffer.readSSHBuffer(),
              let eData = e.getData(at: 0, length: e.readableBytes),
              let nData = n.getData(at: 0, length: n.readableBytes),
              !eData.isEmpty, !nData.isEmpty else {
            throw RSAHostKeyError.malformedPublicKey
        }
        return Self(exponent: eData, modulus: nData)
    }
}

// MARK: - KEXINIT 广播类型

/// 只为把 "rsa-sha2-256" 送进 KEXINIT 主机密钥算法清单。
/// blob 解析与签名验证实际由 RSASSHHostKey 完成（blob 的 key type 是
/// "ssh-rsa"，NIOSSH 按名字路由不到这里）；这里的解析/验签为完整起见
/// 同样正确实现（复用 RSASSHHostKey），避免留下"调了就炸"的死代码。
public struct RSASHA256AdvertisedKey: NIOSSHPublicKeyProtocol {
    public static let publicKeyPrefix = "rsa-sha2-256"
    private let inner: RSASSHHostKey

    private init(inner: RSASSHHostKey) { self.inner = inner }

    public var rawRepresentation: Data { inner.rawRepresentation }

    public func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        inner.isValidSignature(signature, for: data)
    }

    public func write(to buffer: inout ByteBuffer) -> Int {
        inner.write(to: &buffer)
    }

    public static func read(from buffer: inout ByteBuffer) throws -> Self {
        Self(inner: try RSASSHHostKey.read(from: &buffer))
    }
}

/// 只为把 "rsa-sha2-512" 送进 KEXINIT 主机密钥算法清单，其余同上。
public struct RSASHA512AdvertisedKey: NIOSSHPublicKeyProtocol {
    public static let publicKeyPrefix = "rsa-sha2-512"
    private let inner: RSASSHHostKey

    private init(inner: RSASSHHostKey) { self.inner = inner }

    public var rawRepresentation: Data { inner.rawRepresentation }

    public func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        inner.isValidSignature(signature, for: data)
    }

    public func write(to buffer: inout ByteBuffer) -> Int {
        inner.write(to: &buffer)
    }

    public static func read(from buffer: inout ByteBuffer) throws -> Self {
        Self(inner: try RSASSHHostKey.read(from: &buffer))
    }
}

// MARK: - SecKey 构造（X.509 SPKI）

/// 把 SSH 的 (e, n) 组装成 SecKey 可用的 RSA 公钥。
private enum RSASecKey {
    static func publicKey(modulus n: Data, exponent e: Data) -> SecKey? {
        guard !n.isEmpty, !e.isEmpty, let spki = spkiDER(modulus: n, exponent: e) else {
            return nil
        }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(spki as CFData, attrs as CFDictionary, &error) else {
            return nil
        }
        return key
    }

    private static func derLength(_ count: Int) -> Data {
        precondition(count >= 0)
        if count < 128 {
            return Data([UInt8(count)])
        }
        var len = count
        var bytes: [UInt8] = []
        while len > 0 {
            bytes.insert(UInt8(len & 0xFF), at: 0)
            len >>= 8
        }
        return Data([UInt8(0x80 | bytes.count)] + bytes)
    }

    private static func derInteger(_ raw: Data) -> Data {
        // SSH mpint 本来就是大端补码，与 DER INTEGER 的字节规则一致；
        // 这里只做规范化：去掉多余前导零，正数高位为 1 时补 0x00。
        var bytes = raw
        while bytes.count > 1 && bytes.first == 0x00 { bytes.removeFirst() }
        guard let first = bytes.first else { return Data([0x02, 0x01, 0x00]) }
        if first & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        return Data([0x02]) + derLength(bytes.count) + bytes
    }

    private static func derSequence(_ body: Data) -> Data {
        Data([0x30]) + derLength(body.count) + body
    }

    private static func spkiDER(modulus n: Data, exponent e: Data) -> Data {
        // PKCS#1 RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        let pkcs1 = derSequence(derInteger(n) + derInteger(e))
        // AlgorithmIdentifier ::= SEQUENCE { OID rsaEncryption (1.2.840.113549.1.1.1), NULL }
        let oidRSA: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        let algId = derSequence(Data(oidRSA) + Data([0x05, 0x00]))
        // BIT STRING 包裹 PKCS#1（首字节 0x00 表示无未用比特）
        let bitString = Data([0x03]) + derLength(pkcs1.count + 1) + Data([0x00]) + pkcs1
        return derSequence(algId + bitString)
    }
}
