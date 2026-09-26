import Foundation

/// 一台远程服务器的配置。密码不存这里，只存 Keychain。
struct ServerConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String

    var displayAddress: String { "\(username)@\(host):\(port)" }
}

/// SFTP 目录条目。
struct RemoteEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64?
}

/// 文档位置：本地文件 / 远程文件。
enum DocumentLocation: Hashable {
    case local(URL)
    case remote(serverID: UUID, serverName: String, path: String)
}

/// 一个打开的编辑器标签页。只在主线程（@MainActor）上使用。
@MainActor
final class OpenDocument: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var text: String = ""
    @Published var isLoading = false
    @Published var loadError: String?

    let fileExtension: String
    let location: DocumentLocation

    private var savedText: String = ""

    var isDirty: Bool { text != savedText }

    init(title: String, fileExtension: String, location: DocumentLocation) {
        self.title = title
        self.fileExtension = fileExtension
        self.location = location
    }

    func markSaved() {
        savedText = text
    }
}
