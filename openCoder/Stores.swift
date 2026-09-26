import Foundation
import Combine

/// App 设置：自动换行、行号显示。
@MainActor
final class SettingsStore: ObservableObject {
    @Published var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "opencoder.wordWrap") }
    }
    @Published var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "opencoder.showLineNumbers") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.wordWrap = defaults.object(forKey: "opencoder.wordWrap") as? Bool ?? true
        self.showLineNumbers = defaults.object(forKey: "opencoder.showLineNumbers") as? Bool ?? true
    }
}

/// 服务器配置存取（密码除外，密码在 Keychain）。
@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [ServerConfig] = []

    private let storageKey = "opencoder.servers"

    init() {
        load()
    }

    func server(id: UUID) -> ServerConfig? {
        servers.first { $0.id == id }
    }

    func add(_ server: ServerConfig, password: String) {
        servers.append(server)
        KeychainStore.save(password, account: KeychainStore.passwordAccount(for: server.id))
        persist()
    }

    func update(_ server: ServerConfig, password: String?) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let old = servers[index]
        servers[index] = server
        if let password {
            KeychainStore.save(password, account: KeychainStore.passwordAccount(for: server.id))
        }
        // 主机或端口变了：旧 pin 作废、断开旧连接，下次连接重新 TOFU
        if old.host != server.host || old.port != server.port {
            HostKeyPinStore.shared.forget(key: HostKeyPinStore.pinKey(host: old.host, port: old.port))
            Task { await SSHManager.shared.disconnect(serverID: server.id) }
        }
        persist()
    }

    func delete(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        KeychainStore.delete(account: KeychainStore.passwordAccount(for: server.id))
        HostKeyPinStore.shared.forget(key: HostKeyPinStore.pinKey(host: server.host, port: server.port))
        Task { await SSHManager.shared.disconnect(serverID: server.id) }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) else { return }
        servers = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
