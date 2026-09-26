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
        migrateHiddenFilesToTrash()
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

    // MARK: - 移出列表（只从文件列表移除记录，文件本身保留在设备上）

    /// "移出列表"的真实去向：Documents 下的隐藏目录。
    /// 点开头目录会被文件列表（.skipsHiddenFiles）与系统导入选择器自动隐藏，
    /// 因此被移出的文件不会再出现在导入清单里，也不可能"复活"。
    /// iOS 没有废纸篓，FileManager.trashItem 不可用；按用户要求，
    /// 文件列表的"删除"只删记录、不删文件。
    static var trashDirectory: URL {
        documentsDirectory.appendingPathComponent(".opencoder_trash", isDirectory: true)
    }

    /// 把文件/文件夹搬进回收站（重名时自动加序号），成功返回 true。
    func trashFile(_ url: URL) -> Bool {
        // 别把回收站自己搬进去
        guard url.standardized.path != Self.trashDirectory.standardized.path else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.trashDirectory, withIntermediateDirectories: true)
            let dest = uniqueTrashURL(for: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return true
        } catch {
            return false
        }
    }

    private func uniqueTrashURL(for name: String) -> URL {
        let trash = Self.trashDirectory
        var dest = trash.appendingPathComponent(name)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            i += 1
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let newName = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            dest = trash.appendingPathComponent(newName)
        }
        return dest
    }

    /// 旧版（v13.x）用 UserDefaults 存隐藏文件名集合；v14 起改用回收站目录。
    /// 启动时把旧记录对应的文件搬进回收站，然后清掉旧 key，保证行为一致。
    private func migrateHiddenFilesToTrash() {
        let key = "opencoder.hiddenLocalFiles"
        guard let saved = UserDefaults.standard.stringArray(forKey: key), !saved.isEmpty else { return }
        let trashPath = Self.trashDirectory.standardized.path
        for rel in saved {
            let src = Self.documentsDirectory.appendingPathComponent(rel)
            let srcPath = src.standardized.path
            guard srcPath != trashPath, !srcPath.hasPrefix(trashPath + "/"),
                  FileManager.default.fileExists(atPath: srcPath) else { continue }
            _ = trashFile(src)
        }
        UserDefaults.standard.removeObject(forKey: key)
    }
}
