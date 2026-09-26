import SwiftUI
import UniformTypeIdentifiers

/// 本地文件浏览器：浏览 Documents 目录，支持新建 / 重命名 / 删除 / 导入。
@MainActor
struct FileBrowserView: View {
    let directory: URL
    @ObservedObject var documents: DocumentManager
    @Binding var path: [FileNav]

    @State private var items: [URL] = []
    @State private var newName = ""
    @State private var showNewFileAlert = false
    @State private var showNewFolderAlert = false
    @State private var showImporter = false
    @State private var renameTarget: URL?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyState(icon: "folder", title: "文件夹为空")
            } else {
                List {
                    ForEach(items, id: \.self) { url in
                        Button(action: { open(url) }) {
                            HStack {
                                Image(systemName: isDirectory(url) ? "folder.fill" : "doc.text")
                                    .foregroundColor(isDirectory(url) ? .accentColor : .secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                if isDirectory(url) {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button("重命名") { renameTarget = url; newName = url.lastPathComponent }
                            Button("移出列表", role: .destructive) { delete(url) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("移出列表", role: .destructive) { delete(url) }
                        }
                    }
                }
            }
        }
        .navigationTitle(directory.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { newName = ""; showNewFolderAlert = true }) {
                    Image(systemName: "folder.badge.plus")
                }
                Button(action: { newName = ""; showNewFileAlert = true }) {
                    Image(systemName: "doc.badge.plus")
                }
                Button(action: { showImporter = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                fail(error.localizedDescription)
            }
        }
        .alert("新建文件", isPresented: $showNewFileAlert) {
            TextField("文件名，如 notes.txt", text: $newName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button("创建") { createFile() }
            Button("取消", role: .cancel) {}
        }
        .alert("新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("文件夹名", text: $newName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button("创建") { createFolder() }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $newName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button("确定") { rename() }
            Button("取消", role: .cancel) {}
        }
        .alert("出错了", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 逻辑

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        // 用户从列表移除的记录不再显示，文件本身仍在磁盘上。
        items = urls.filter { !documents.isHiddenLocalFile($0) }.sorted {
            let d0 = isDirectory($0), d1 = isDirectory($1)
            if d0 != d1 { return d0 }
            return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func open(_ url: URL) {
        if isDirectory(url) {
            path.append(.folder(url))
        } else {
            documents.openLocalFile(url: url)
            path.append(.editor)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func createFile() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let url = directory.appendingPathComponent(name)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            documents.unhideLocalFile(url)
            reload()
            documents.openLocalFile(url: url)
            path.append(.editor)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func createFolder() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            documents.unhideLocalFile(url)
            reload()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func rename() {
        guard let target = renameTarget else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != target.lastPathComponent else { return }
        let dest = target.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: target, to: dest)
            documents.unhideLocalFile(dest)
            reload()
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// 从列表移除：只删记录，文件保留在磁盘上。
    /// 注意 iOS 没有废纸篓，FileManager.trashItem 会直接抛"功能不受支持"，
    /// 此前报错的根因即在此。
    private func delete(_ url: URL) {
        documents.hideLocalFile(url)
        documents.closeDocuments(at: url)
        reload()
        ToastCenter.shared.show("已从列表移除，文件保留在设备中")
    }

    private func importFiles(_ urls: [URL]) {
        var count = 0
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let dest = directory.appendingPathComponent(url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                documents.unhideLocalFile(dest)
                count += 1
            }
        }
        reload()
        if count > 0 {
            ToastCenter.shared.show("已导入 \(count) 个文件")
        } else if !urls.isEmpty {
            fail("导入失败：文件已存在或无法读取")
        }
    }
}
