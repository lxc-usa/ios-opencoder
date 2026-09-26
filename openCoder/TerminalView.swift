import SwiftUI

/// SSH 命令控制台：输入命令、执行并查看合并输出。
/// 注意：每条命令在独立 channel 中执行，无持久 shell（cd 等状态不保留）。
@MainActor
struct TerminalView: View {
    let serverID: UUID
    @ObservedObject var servers: ServerStore
    @ObservedObject var settings: SettingsStore

    @State private var command = ""
    @State private var lines: [TerminalLine] = []
    @State private var isRunning = false
    @State private var showInfo = false

    private var outputFont: Font {
        settings.monoFont.font(size: settings.monoFontSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if lines.isEmpty {
                            Text("输入下方命令并运行，如：ls -la")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(outputFont)
                                .lineSpacing(settings.lineSpacing)
                                .foregroundColor(line.isError ? .red : (line.isCommand ? .accentColor : .primary))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("输入命令", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(outputFont)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onSubmit(run)
                    .disabled(isRunning)
                if isRunning {
                    ProgressView()
                } else {
                    Button("运行", action: run)
                        .buttonStyle(.borderedProminent)
                        .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationTitle("SSH 命令")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    lines.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(lines.isEmpty || isRunning)
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .popover(isPresented: $showInfo) {
            Text("每条命令在独立通道中执行，不保留 cd 等状态；输出为命令的标准输出与标准错误的合并结果。")
                .font(.callout)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }

    private func run() {
        guard let server = servers.server(id: serverID) else {
            lines.append(TerminalLine(text: "服务器不存在", isCommand: false, isError: true))
            return
        }
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        command = ""
        lines.append(TerminalLine(text: "$ " + cmd, isCommand: true, isError: false))
        isRunning = true
        Task {
            do {
                let result = try await SSHManager.shared.runCommand(server: server, command: cmd)
                lines.append(TerminalLine(
                    text: result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(无输出)" : result,
                    isCommand: false,
                    isError: false
                ))
            } catch {
                lines.append(TerminalLine(text: "错误：\(error.localizedDescription)", isCommand: false, isError: true))
            }
            isRunning = false
        }
    }
}

private struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let isCommand: Bool
    let isError: Bool
}
