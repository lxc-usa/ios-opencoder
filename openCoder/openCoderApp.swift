import SwiftUI
import Combine

@main
struct openCoderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

/// App 级状态持有者：设置、服务器、打开的文档。
///
/// 设置变化会转发为 AppState 的变化，这样根视图的 `.preferredColorScheme`
/// 等依赖设置的修饰符能在切换后即时生效。
@MainActor
final class AppState: ObservableObject {
    let settings: SettingsStore
    let servers: ServerStore
    let documents: DocumentManager

    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = SettingsStore()
        let servers = ServerStore()
        self.settings = settings
        self.servers = servers
        self.documents = DocumentManager(servers: servers)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

@MainActor
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            FilesTabView(documents: appState.documents, settings: appState.settings)
                .tabItem { Label("文件", systemImage: "folder") }
            ServersTabView(servers: appState.servers, documents: appState.documents, settings: appState.settings)
                .tabItem { Label("服务器", systemImage: "server.rack") }
            SettingsView(settings: appState.settings)
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .dsToast()
        .preferredColorScheme(appState.settings.appColorScheme.preferred)
    }
}

// MARK: - 文件 Tab

enum FileNav: Hashable {
    case editor
    case folder(URL)
}

@MainActor
struct FilesTabView: View {
    @ObservedObject var documents: DocumentManager
    @ObservedObject var settings: SettingsStore
    @State private var path: [FileNav] = []

    var body: some View {
        NavigationStack(path: $path) {
            FileBrowserView(directory: DocumentManager.documentsDirectory, documents: documents, path: $path)
                .navigationDestination(for: FileNav.self) { nav in
                    switch nav {
                    case .editor:
                        EditorHostView(documents: documents, settings: settings)
                    case .folder(let url):
                        FileBrowserView(directory: url, documents: documents, path: $path)
                    }
                }
        }
    }
}

// MARK: - 服务器 Tab

enum ServerNav: Hashable {
    case browser(serverID: UUID, path: String)
    case terminal(serverID: UUID)
    case editor
}

@MainActor
struct ServersTabView: View {
    @ObservedObject var servers: ServerStore
    @ObservedObject var documents: DocumentManager
    @ObservedObject var settings: SettingsStore
    @State private var path: [ServerNav] = []

    var body: some View {
        NavigationStack(path: $path) {
            ServerListView(servers: servers, path: $path)
                .navigationDestination(for: ServerNav.self) { nav in
                    switch nav {
                    case .browser(let serverID, let dirPath):
                        SFTPBrowserView(serverID: serverID, path: dirPath, servers: servers, documents: documents, navPath: $path)
                    case .terminal(let serverID):
                        TerminalView(serverID: serverID, servers: servers, settings: settings)
                    case .editor:
                        EditorHostView(documents: documents, settings: settings)
                    }
                }
        }
    }
}
