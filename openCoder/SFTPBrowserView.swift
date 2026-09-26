import SwiftUI

/// SFTP 远程目录浏览：进入子目录、打开文件进行编辑。
@MainActor
struct SFTPBrowserView: View {
    let serverID: UUID
    let path: String
    @ObservedObject var servers: ServerStore
    @ObservedObject var documents: DocumentManager
    @Binding var navPath: [ServerNav]

    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openingFileName: String?

    private var server: ServerConfig? { servers.server(id: serverID) }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在连接…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "连接失败",
                    message: errorMessage,
                    actionTitle: "重试",
                    action: load
                )
            } else if entries.isEmpty {
                EmptyState(icon: "folder", title: "空目录")
            } else {
                List(entries) { entry in
                    Button(action: { open(entry) }) {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .lineLimit(1)
                                if let size = entry.size, !entry.isDirectory {
                                    Text(formattedSize(size))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if entry.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(openingFileName != nil)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: load) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if let name = openingFileName {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在打开 \(name)…")
                        .font(.caption)
                }
                .padding(24)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .shadow(radius: 8)
            }
        }
        .onAppear(perform: load)
    }

    private var navigationTitle: String {
        if path == "." || path == "/" { return server?.name ?? "远程目录" }
        return (path as NSString).lastPathComponent
    }

    private func formattedSize(_ size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func load() {
        guard let server else {
            errorMessage = "服务器不存在"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                entries = try await SSHManager.shared.listDirectory(server: server, path: path)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func open(_ entry: RemoteEntry) {
        guard let server else { return }
        if entry.isDirectory {
            navPath.append(.browser(serverID: serverID, path: entry.path))
        } else {
            openingFileName = entry.name
            Task {
                await documents.openRemoteFile(server: server, path: entry.path)
                openingFileName = nil
                navPath.append(.editor)
            }
        }
    }
}
