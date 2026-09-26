import Foundation
@preconcurrency import Citadel
import NIOSSH
import NIO

enum SSHManagerError: LocalizedError {
    case missingPassword
    case hostKeyMismatch(host: String)
    case cannotSerializeHostKey
    /// 带阶段上下文的连接/操作错误：underlying 的原始信息通过 describeSSHError 转成中文。
    case connectionFailed(stage: String, underlying: Error)
    /// 握手算法协商失败：已自动抓取服务器 KEXINIT，把双方算法清单摆出来，不再靠猜。
    case handshakeFailed(host: String, port: Int, probe: SSHKexProbe.Result?, raw: String)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "Keychain 中没有该服务器的密码，请重新编辑服务器并填写密码"
        case .hostKeyMismatch(let host):
            return "⚠️ \(host) 的主机密钥与首次连接时记录的不一致，可能遭遇中间人攻击，已拒绝连接"
        case .cannotSerializeHostKey:
            return "无法读取服务器主机密钥"
        case .connectionFailed(let stage, let underlying):
            return "\(stage)失败：\(describeSSHError(underlying))"
        case .handshakeFailed(let host, let port, let probe, let raw):
            var lines = ["连接 \(host):\(port) 失败：SSH 算法协商不一致。"]
            if let p = probe, !p.isEmpty {
                lines.append("")
                lines.append("【服务器提供】\(p.banner)")
                lines.append("• 密钥交换：\(p.keyExchange.joined(separator: ", "))")
                lines.append("• 主机密钥：\(p.hostKey.joined(separator: ", "))")
                lines.append("• 加密(去)：\(p.encryptionC2S.joined(separator: ", "))")
                lines.append("• 加密(回)：\(p.encryptionS2C.joined(separator: ", "))")
                lines.append("• MAC(去)：\(p.macC2S.joined(separator: ", "))")
                lines.append("• MAC(回)：\(p.macS2C.joined(separator: ", "))")
                lines.append("")
                lines.append("【本 App 提供】")
                lines.append("• 密钥交换：\(SSHKexProbe.ourKeyExchange)")
                lines.append("• 主机密钥：\(SSHKexProbe.ourHostKey)")
                lines.append("• 加密：\(SSHKexProbe.ourEncryption)")
                lines.append("• MAC：\(SSHKexProbe.ourMac)")
            } else {
                lines.append("（未能读取服务器算法清单，请把这条完整信息发给开发者定位）")
            }
            lines.append("")
            lines.append("原始错误：\(raw)")
            return lines.joined(separator: "\n")
        }
    }
}

/// 把底层错误转成中文说明。
/// 背景：NIOSSHError 是 struct，它的 diagnostics 是私有的，`localizedDescription`
/// 只能显示 "The operation couldn't be completed. (NIOSSH.NIOSSHError error 1.)"，
/// 真正的原因藏在公开的 `type` 字段里。这里把它挖出来。
func describeSSHError(_ error: Error) -> String {
    if let e = error as? SSHManagerError {
        // 避免双重包装
        if case .connectionFailed = e { return e.errorDescription ?? "连接失败" }
        return e.errorDescription ?? "SSH 错误"
    }
    if let e = error as? SSHClientError {
        switch e {
        case .allAuthenticationOptionsFailed:
            return "身份认证失败：服务器拒绝了用户名/密码，请检查用户名和密码是否正确"
        case .unsupportedPasswordAuthentication:
            return "服务器不支持密码认证"
        case .unsupportedPrivateKeyAuthentication:
            return "服务器不支持私钥认证"
        case .unsupportedHostBasedAuthentication:
            return "服务器不支持 host-based 认证"
        case .channelCreationFailed:
            return "SSH 通道创建失败"
        }
    }
    if let e = error as? NIOSSHError {
        let t = e.type
        // 原始细节（包含私有 diagnostics 的文本形式），兜底时展示
        let raw = String(describing: e)
        switch t {
        case .keyExchangeNegotiationFailure:
            // 注意：NIOSSH 在密钥交换、主机密钥、加密、MAC 任一环节无交集，
            // 或双向协商结果不对称时都抛这个错，不只是"密钥交换算法"。
            return "SSH 握手失败：算法协商不一致（密钥交换 / 主机密钥 / 加密 / MAC 任一环节没有共同选项）（\(raw)）"
        case .unsupportedVersion:
            return "SSH 握手失败：服务器的 SSH 版本不受支持（\(raw)）"
        case .invalidExchangeHashSignature:
            return "SSH 握手失败：服务器主机密钥签名校验未通过（\(raw)）"
        case .invalidHostKeyForKeyExchange:
            return "SSH 握手失败：服务器发送的主机密钥与协商的不一致（\(raw)）"
        case .tcpShutdown:
            return "连接被中断：TCP 在 SSH 会话结束前关闭（\(raw)）"
        case .creatingChannelAfterClosure:
            return "SSH 连接已关闭，无法再打开通道，请重试（\(raw)）"
        case .channelSetupRejected:
            return "服务器拒绝了通道请求（\(raw)）"
        case .protocolViolation:
            return "SSH 协议异常（\(raw)）"
        case .invalidPacketFormat, .invalidSSHMessage, .unknownPacketType:
            return "收到无法解析的 SSH 数据包（\(raw)）"
        default:
            return "SSH 协议错误（\(raw)）"
        }
    }
    if let e = error as? SFTPError {
        switch e {
        case .missingResponse:
            return "SFTP 无响应：15 秒内没有收到服务器回复，可能是打开的 SFTP 句柄太多"
        case .connectionClosed:
            return "SFTP 连接已关闭"
        case .errorStatus(let status):
            return "SFTP 操作被服务器拒绝（\(status)）"
        case .unsupportedVersion(let v):
            return "SFTP 版本不受支持（\(v)）"
        default:
            return "SFTP 错误（\(String(describing: e))）"
        }
    }
    return error.localizedDescription
}

/// 是否为算法协商失败。
/// NIOSSHError 的 diagnostics 是私有的，只能比对公开的 `type`；再加字符串兜底，
/// 防止 Citadel 在外层包了一层别的 Error 类型。
func isKeyExchangeNegotiationFailure(_ error: Error) -> Bool {
    if let e = error as? NIOSSHError, e.type == .keyExchangeNegotiationFailure { return true }
    return String(describing: error).contains("keyExchangeNegotiationFailure")
}

/// 主机密钥 TOFU 存储：pinKey（"host:port"）-> 主机密钥字节的 base64。单例，线程安全。
/// 用 host:port 而不是只用 host：同一主机不同端口可能是完全不同的服务器。
final class HostKeyPinStore: @unchecked Sendable {
    static let shared = HostKeyPinStore()

    private let lock = NSLock()
    private var pins: [String: String]
    private let defaultsKey = "opencoder.hostKeyPins"

    private init() {
        pins = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    static func pinKey(host: String, port: Int) -> String { "\(host):\(port)" }

    func pinned(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pins[key]
    }

    func pin(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        pins[key] = value
        UserDefaults.standard.set(pins, forKey: defaultsKey)
    }

    func forget(key: String) {
        lock.lock()
        defer { lock.unlock() }
        pins.removeValue(forKey: key)
        UserDefaults.standard.set(pins, forKey: defaultsKey)
    }
}

/// TOFU 主机密钥校验器：首次连接记录主机密钥，之后不一致则拒绝。
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let pinKey: String
    private let displayHost: String

    init(host: String, port: Int) {
        self.pinKey = HostKeyPinStore.pinKey(host: host, port: port)
        self.displayHost = "\(host):\(port)"
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        let written = hostKey.write(to: &buffer)
        guard written > 0, let bytes = buffer.getBytes(at: 0, length: written) else {
            validationCompletePromise.fail(SSHManagerError.cannotSerializeHostKey)
            return
        }
        let fingerprint = Data(bytes).base64EncodedString()
        if let pinned = HostKeyPinStore.shared.pinned(forKey: pinKey) {
            if pinned == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHManagerError.hostKeyMismatch(host: displayHost))
            }
        } else {
            HostKeyPinStore.shared.pin(key: pinKey, value: fingerprint)
            validationCompletePromise.succeed(())
        }
    }
}

/// SSH / SFTP 连接管理：每个服务器复用一个 SSHClient。
actor SSHManager {
    static let shared = SSHManager()

    private var clients: [UUID: SSHClient] = [:]

    private init() {}

    // MARK: - 连接

    func client(for server: ServerConfig) async throws -> SSHClient {
        if let existing = clients[server.id] {
            // 缓存的连接断开后不能再复用：channel 已死时 openSFTP 会抛
            // NIOSSHError.creatingChannelAfterClosure，必须丢弃重连。
            if existing.isConnected {
                return existing
            }
            clients.removeValue(forKey: server.id)
        }
        guard let password = KeychainStore.load(account: KeychainStore.passwordAccount(for: server.id)) else {
            throw SSHManagerError.missingPassword
        }
        let username = server.username
        var settings = SSHClientSettings(
            host: server.host,
            port: server.port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: server.host, port: server.port))
        )
        // Citadel 推荐的兼容算法集：NIOSSH 默认不支持 ssh-rsa 主机密钥，
        // 这里补上 RSA 主机密钥、DH group14 密钥交换和 AES128CTR。
        //
        // 注意：依赖的 swift-nio-ssh fork 默认只带 AES-GCM 加密套件；
        // 实测某些服务器既不提供 GCM 也不提供 aes128-ctr，这里再补上
        // aes256-ctr / aes192-ctr（本 App 内实现，见 AESCTRCiphers.swift），
        // 否则握手会报 NIOSSHError.keyExchangeNegotiationFailure。
        var sshAlgorithms = SSHAlgorithms.all
        sshAlgorithms.transportProtectionSchemes = .add([
            AES256CTRTransportProtection.self,
            AES192CTRTransportProtection.self,
            AES128CTR.self,
        ])
        settings.algorithms = sshAlgorithms
        do {
            let client = try await SSHClient.connect(to: settings)
            clients[server.id] = client
            return client
        } catch {
            if isKeyExchangeNegotiationFailure(error) {
                // 算法协商失败：自动抓服务器 KEXINIT，把双方清单摆出来，不再靠猜。
                let probe = await SSHKexProbe.probe(host: server.host, port: server.port)
                throw SSHManagerError.handshakeFailed(
                    host: server.host,
                    port: server.port,
                    probe: probe,
                    raw: String(describing: error)
                )
            }
            throw SSHManagerError.connectionFailed(
                stage: "连接 \(server.host):\(server.port)",
                underlying: error
            )
        }
    }

    func disconnect(serverID: UUID) async {
        if let client = clients.removeValue(forKey: serverID) {
            try? await client.close()
        }
    }

    func disconnectAll() async {
        let all = Array(clients.values)
        clients.removeAll()
        for client in all {
            try? await client.close()
        }
    }

    // MARK: - SFTP

    func listDirectory(server: ServerConfig, path: String) async throws -> [RemoteEntry] {
        do {
            return try await listDirectoryInner(server: server, path: path)
        } catch let e as SSHManagerError {
            throw e
        } catch {
            throw SSHManagerError.connectionFailed(stage: "读取目录 \(path)", underlying: error)
        }
    }

    private func listDirectoryInner(server: ServerConfig, path: String) async throws -> [RemoteEntry] {
        let client = try await client(for: server)
        let sftp = try await client.openSFTP()
        // 解析为绝对路径，避免 "./" 前缀在后续读写中累积
        let basePath = try await sftp.getRealPath(atPath: path)
        let listing = try await sftp.listDirectory(atPath: basePath)
        var entries: [RemoteEntry] = []
        for name in listing {
            for component in name.components {
                guard component.filename != ".", component.filename != ".." else { continue }
                let mode = component.attributes.permissions ?? 0
                let isDir = (mode & 0o170000) == 0o040000 || component.longname.hasPrefix("d")
                let fullPath = basePath == "/" ? "/\(component.filename)" : "\(basePath)/\(component.filename)"
                entries.append(RemoteEntry(
                    name: component.filename,
                    path: fullPath,
                    isDirectory: isDir,
                    size: component.attributes.size
                ))
            }
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func readFile(server: ServerConfig, path: String) async throws -> String {
        do {
            let client = try await client(for: server)
            let sftp = try await client.openSFTP()
            var buffer = try await sftp.withFile(filePath: path, flags: .read) { file in
                try await file.readAll()
            }
            return buffer.readString(length: buffer.readableBytes) ?? ""
        } catch let e as SSHManagerError {
            throw e
        } catch {
            throw SSHManagerError.connectionFailed(stage: "读取文件 \(path)", underlying: error)
        }
    }

    func writeFile(server: ServerConfig, path: String, text: String) async throws {
        do {
            let client = try await client(for: server)
            let sftp = try await client.openSFTP()
            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            let data = buffer
            try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                try await file.write(data, at: 0)
            }
        } catch let e as SSHManagerError {
            throw e
        } catch {
            throw SSHManagerError.connectionFailed(stage: "保存文件 \(path)", underlying: error)
        }
    }

    // MARK: - SSH 命令

    /// 执行一条非交互式命令，返回 stdout 文本。
    /// 注意：每条命令在独立 channel 中执行，无持久 shell（cd 等状态不保留）；
    /// 命令若向 stderr 输出或返回非零退出码，Citadel 会抛错。
    func runCommand(server: ServerConfig, command: String) async throws -> String {
        do {
            let client = try await client(for: server)
            var output = try await client.executeCommand(command)
            return output.readString(length: output.readableBytes) ?? ""
        } catch let e as SSHManagerError {
            throw e
        } catch {
            throw SSHManagerError.connectionFailed(stage: "执行命令", underlying: error)
        }
    }
}
