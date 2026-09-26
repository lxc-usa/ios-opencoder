import Foundation

enum DocumentError: LocalizedError {
    case serverGone

    var errorDescription: String? {
        switch self {
        case .serverGone: return "服务器配置已删除，无法保存"
        }
    }
}

/// 打开的文档（标签页）管理。
@MainActor
final class DocumentManager: ObservableObject {
    @Published private(set) var documents: [OpenDocument] = []
    @Published var selectedID: UUID?

    private let servers: ServerStore

    init(servers: ServerStore) {
        self.servers = servers
    }

    var selected: OpenDocument? {
        documents.first { $0.id == selectedID }
    }

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 打开

    func openLocalFile(url: URL) {
        if let existing = documents.first(where: { $0.location == .local(url) }) {
            selectedID = existing.id
            return
        }
        let doc = OpenDocument(
            title: url.lastPathComponent,
            fileExtension: url.pathExtension,
            location: .local(url)
        )
        doc.isLoading = true
        documents.append(doc)
        selectedID = doc.id
        Task {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                doc.text = text
                doc.markSaved()
            } catch {
                doc.loadError = error.localizedDescription
            }
            doc.isLoading = false
        }
    }

    /// 从 SFTP 下载并打开远程文件。
    func openRemoteFile(server: ServerConfig, path: String) async {
        let name = (path as NSString).lastPathComponent
        if let existing = documents.first(where: {
            $0.location == .remote(serverID: server.id, serverName: server.name, path: path)
        }) {
            selectedID = existing.id
            return
        }
        let doc = OpenDocument(
            title: name,
            fileExtension: (name as NSString).pathExtension,
            location: .remote(serverID: server.id, serverName: server.name, path: path)
        )
        doc.isLoading = true
        documents.append(doc)
        selectedID = doc.id
        do {
            let text = try await SSHManager.shared.readFile(server: server, path: path)
            doc.text = text
            doc.markSaved()
        } catch {
            doc.loadError = error.localizedDescription
        }
        doc.isLoading = false
    }

    /// 在 Documents 下新建一个空文件并打开。
    func newFile() {
        let base = Self.documentsDirectory
        var url = base.appendingPathComponent("未命名.txt")
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = base.appendingPathComponent("未命名\(index).txt")
        }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        openLocalFile(url: url)
    }

    // MARK: - 保存 / 关闭

    func save(_ doc: OpenDocument) async throws {
        let text = doc.text
        switch doc.location {
        case .local(let url):
            try text.write(to: url, atomically: true, encoding: .utf8)
        case .remote(let serverID, _, let path):
            guard let server = servers.server(id: serverID) else {
                throw DocumentError.serverGone
            }
            try await SSHManager.shared.writeFile(server: server, path: path, text: text)
        }
        doc.markSaved()
    }

    func close(_ doc: OpenDocument) {
        documents.removeAll { $0.id == doc.id }
        if selectedID == doc.id {
            selectedID = documents.last?.id
        }
    }

    func closeAll() {
        documents.removeAll()
        selectedID = nil
    }

    /// 本地文件被删除时，关闭对应的标签页。
    func closeDocuments(at url: URL) {
        let doomed = documents.filter {
            if case .local(let u) = $0.location {
                return u == url || u.path.hasPrefix(url.path + "/")
            }
            return false
        }
        doomed.forEach(close)
    }
}
