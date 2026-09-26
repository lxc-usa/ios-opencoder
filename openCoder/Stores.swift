import Foundation
import Combine
import SwiftUI

/// 配色方案：跟随系统（默认）/ 强制浅色 / 强制深色。
enum AppColorScheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 传给 `.preferredColorScheme` 的值；跟随系统时传 nil。
    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App 设置：自动换行、行号显示、等宽字体、字号与行距（字体相关设置终端与编辑器共用）。
@MainActor
final class SettingsStore: ObservableObject {
    @Published var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "opencoder.wordWrap") }
    }
    @Published var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "opencoder.showLineNumbers") }
    }
    @Published var monoFont: MonoFont {
        didSet { UserDefaults.standard.set(monoFont.rawValue, forKey: "opencoder.monoFont") }
    }
    @Published var monoFontSize: Double {
        didSet { UserDefaults.standard.set(monoFontSize, forKey: "opencoder.monoFontSize") }
    }
    @Published var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "opencoder.lineSpacing") }
    }
    @Published var appColorScheme: AppColorScheme {
        didSet { UserDefaults.standard.set(appColorScheme.rawValue, forKey: "opencoder.appColorScheme") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.wordWrap = defaults.object(forKey: "opencoder.wordWrap") as? Bool ?? true
        self.showLineNumbers = defaults.object(forKey: "opencoder.showLineNumbers") as? Bool ?? true
        // v8 用的是 terminalFont / terminalFontSize 键，保留兼容读取。
        let rawFont = defaults.string(forKey: "opencoder.monoFont")
            ?? defaults.string(forKey: "opencoder.terminalFont") ?? ""
        self.monoFont = MonoFont(rawValue: rawFont) ?? .sfMono
        let savedSize = (defaults.object(forKey: "opencoder.monoFontSize") as? Double)
            ?? (defaults.object(forKey: "opencoder.terminalFontSize") as? Double) ?? 13
        self.monoFontSize = min(max(savedSize, 10), 20)
        let savedSpacing = defaults.object(forKey: "opencoder.lineSpacing") as? Double ?? 2
        self.lineSpacing = min(max(savedSpacing, 0), 12)
        self.appColorScheme = AppColorScheme(rawValue: defaults.string(forKey: "opencoder.appColorScheme") ?? "") ?? .system
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
