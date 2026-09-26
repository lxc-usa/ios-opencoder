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
        loadHiddenLocalFiles()
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

    // MARK: - 列表隐藏（只从文件列表移除记录，文件本身保留在磁盘上）

    /// 被用户从文件列表移除的本地路径（相对 Documents 根目录），持久化保存。
    /// iOS 没有废纸篓，FileManager.trashItem 不可用；按用户要求，
    /// 文件列表的"删除"只删记录、不删文件。
    private(set) var hiddenLocalPaths: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(hiddenLocalPaths), forKey: "opencoder.hiddenLocalFiles")
        }
    }

    /// 相对 Documents 根目录的路径（稳定标识，不随当前浏览目录变化）。
    /// 统一做 NFC 规范化，避免"同名不同 Unicode 写法"产生幽灵副本。
    private func relativeLocalPath(_ url: URL) -> String? {
        let root = Self.documentsDirectory.standardized.path
        let p = url.standardized.path
        guard p == root || p.hasPrefix(root + "/") else { return nil }
        let rel = p == root ? "." : String(p.dropFirst(root.count + 1))
        return rel.precomposedStringWithCanonicalMapping
    }

    /// 该 URL 是否已被用户从列表移除。
    func isHiddenLocalFile(_ url: URL) -> Bool {
        guard let rel = relativeLocalPath(url) else { return false }
        return hiddenLocalPaths.contains(rel)
    }

    /// 从文件列表移除（文件保留在磁盘上）。
    func hideLocalFile(_ url: URL) {
        guard let rel = relativeLocalPath(url) else { return }
        hiddenLocalPaths.insert(rel)
    }

    /// 同名文件重新出现（导入/新建/重命名）时取消隐藏，保证新文件可见。
    func unhideLocalFile(_ url: URL) {
        guard let rel = relativeLocalPath(url) else { return }
        hiddenLocalPaths.remove(rel)
    }

    private func loadHiddenLocalFiles() {
        let saved = UserDefaults.standard.stringArray(forKey: "opencoder.hiddenLocalFiles") ?? []
        hiddenLocalPaths = Set(saved.map { $0.precomposedStringWithCanonicalMapping })
    }
}
