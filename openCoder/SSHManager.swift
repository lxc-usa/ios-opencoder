import Foundation
import Citadel
import NIOSSH
import NIO

enum SSHManagerError: LocalizedError {
    case missingPassword
    case hostKeyMismatch(host: String)
    case cannotSerializeHostKey

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "Keychain 中没有该服务器的密码，请重新编辑服务器并填写密码"
        case .hostKeyMismatch(let host):
            return "⚠️ \(host) 的主机密钥与首次连接时记录的不一致，可能遭遇中间人攻击，已拒绝连接"
        case .cannotSerializeHostKey:
            return "无法读取服务器主机密钥"
        }
    }
}

/// 主机密钥 TOFU 存储：host -> 主机密钥线格式的 base64。单例，线程安全。
final class HostKeyPinStore: @unchecked Sendable {
    static let shared = HostKeyPinStore()

    private let lock = NSLock()
    private var pins: [String: String]
    private let defaultsKey = "opencoder.hostKeyPins"

    private init() {
        pins = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    func pinned(for host: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pins[host]
    }

    func pin(host: String, key: String) {
        lock.lock()
        defer { lock.unlock() }
        pins[host] = key
        UserDefaults.standard.set(pins, forKey: defaultsKey)
    }

    func forget(host: String) {
        lock.lock()
        defer { lock.unlock() }
        pins.removeValue(forKey: host)
        UserDefaults.standard.set(pins, forKey: defaultsKey)
    }
}

/// TOFU 主机密钥校验器：首次连接记录主机密钥，之后不一致则拒绝。
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        let written = hostKey.write(to: &buffer)
        guard written > 0, let bytes = buffer.getBytes(at: 0, length: written) else {
            validationCompletePromise.fail(SSHManagerError.cannotSerializeHostKey)
            return
        }
        let fingerprint = Data(bytes).base64EncodedString()
        if let pinned = HostKeyPinStore.shared.pinned(for: host) {
            if pinned == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHManagerError.hostKeyMismatch(host: host))
            }
        } else {
            HostKeyPinStore.shared.pin(host: host, key: fingerprint)
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
            return existing
        }
        guard let password = KeychainStore.load(account: KeychainStore.passwordAccount(for: server.id)) else {
            throw SSHManagerError.missingPassword
        }
        let username = server.username
        let settings = SSHClientSettings(
            host: server.host,
            port: server.port,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: server.host))
        )
        let client = try await SSHClient.connect(to: settings)
        clients[server.id] = client
        return client
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
        let client = try await client(for: server)
        let sftp = try await client.openSFTP()
        var buffer = try await sftp.withFile(filePath: path, flags: .read) { file in
            try await file.readAll()
        }
        return buffer.readString(length: buffer.readableBytes) ?? ""
    }

    func writeFile(server: ServerConfig, path: String, text: String) async throws {
        let client = try await client(for: server)
        let sftp = try await client.openSFTP()
        var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let data = buffer
        try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
            try await file.write(data, at: 0)
        }
    }

    // MARK: - SSH 命令

    /// 执行一条非交互式命令，返回 stdout 文本。
    /// 注意：每条命令在独立 channel 中执行，无持久 shell（cd 等状态不保留）；
    /// 命令若向 stderr 输出或返回非零退出码，Citadel 会抛错。
    func runCommand(server: ServerConfig, command: String) async throws -> String {
        let client = try await client(for: server)
        var output = try await client.executeCommand(command)
        return output.readString(length: output.readableBytes) ?? ""
    }
}
