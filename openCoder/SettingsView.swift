import SwiftUI

/// App 设置。
@MainActor
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DSGroupCard(title: "外观") {
                        SettingRow(icon: "circle.lefthalf.filled", iconTint: .blue, title: "配色方案") {
                            Picker("", selection: $settings.appColorScheme) {
                                ForEach(AppColorScheme.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 230)
                        }
                    }

                    DSGroupCard(title: "编辑器") {
                        SettingRow(icon: "text.wrap", iconTint: .blue, title: "自动换行") {
                            Toggle("", isOn: $settings.wordWrap)
                                .labelsHidden()
                        }
                        SettingDivider()
                        SettingRow(icon: "list.number", iconTint: .blue, title: "显示行号") {
                            Toggle("", isOn: $settings.showLineNumbers)
                                .labelsHidden()
                        }
                    }

                    DSGroupCard(title: "字体与排版") {
                        NavigationLink {
                            MonoFontPickerView(settings: settings)
                        } label: {
                            SettingRow(icon: "textformat", iconTint: .purple, title: "字体") {
                                HStack(spacing: 6) {
                                    Text(settings.monoFont.displayName)
                                        .font(DSFonts.base)
                                        .foregroundColor(DSColors.muted)
                                    Image(systemName: "chevron.right")
                                        .font(DSFonts.smBold)
                                        .foregroundColor(DSColors.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        SettingDivider()
                        SettingRow(icon: "textformat.size", iconTint: .purple, title: "字号") {
                            HStack(spacing: 8) {
                                Text("\(Int(settings.monoFontSize)) pt")
                                    .font(DSFonts.base)
                                    .foregroundColor(DSColors.muted)
                                    .monospacedDigit()
                                Stepper("", value: $settings.monoFontSize, in: 10...20, step: 1)
                                    .labelsHidden()
                            }
                        }
                        SettingDivider()
                        SettingRow(icon: "arrow.up.and.down.text.horizontal", iconTint: .purple, title: "行距") {
                            HStack(spacing: 8) {
                                Text("\(Int(settings.lineSpacing)) pt")
                                    .font(DSFonts.base)
                                    .foregroundColor(DSColors.muted)
                                    .monospacedDigit()
                                Stepper("", value: $settings.lineSpacing, in: 0...12, step: 1)
                                    .labelsHidden()
                            }
                        }
                        SettingDivider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("预览")
                                .font(DSFonts.sm)
                                .foregroundColor(DSColors.muted)
                            Text("$ ls -la\ntotal 48\ndrwxr-xr-x 12 root root 4096 09-26 13:55 .")
                                .font(settings.monoFont.font(size: settings.monoFontSize))
                                .lineSpacing(settings.lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.systemBackground))
                                .cornerRadius(DSSpace.radiusSM)
                        }
                        .padding(.horizontal, DSSpace.base)
                        .padding(.vertical, 10)
                    }
                    Text("字体、字号、行距同时应用于终端与代码编辑器。")
                        .font(DSFonts.sm)
                        .foregroundColor(DSColors.muted)
                        .padding(.horizontal, DSSpace.base)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DSGroupCard(title: "连接") {
                        SettingRow(icon: "apple.terminal", iconTint: .blue, title: "终端会话保持") {
                            Toggle("", isOn: $settings.terminalResumeSession)
                                .labelsHidden()
                        }
                        SettingDivider()
                        Button(role: .destructive) {
                            showDisconnectConfirm = true
                        } label: {
                            SettingRow(
                                icon: "cable.connector.slash",
                                iconTint: DSColors.destructive,
                                title: "断开所有服务器连接",
                                titleColor: DSColors.destructive
                            ) {
                                EmptyView()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("打开后，离开终端再回来会继续之前的会话（当前目录、运行中的程序都保留）；关闭则每次进入终端都是全新会话。")
                        .font(DSFonts.sm)
                        .foregroundColor(DSColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, -14)
                    Text("断开后下次操作时会自动重连。")
                        .font(DSFonts.sm)
                        .foregroundColor(DSColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, -14)

                    DSGroupCard(title: "安全") {
                        Text("服务器密码只保存在本机 Keychain 中。首次连接会记录服务器主机密钥，之后若主机密钥变化将拒绝连接。")
                            .font(DSFonts.sm)
                            .foregroundColor(DSColors.muted)
                            .padding(DSSpace.base)
                    }

                    DSGroupCard(title: "关于") {
                        SettingRow(icon: "app.badge", title: "版本", value: "v15")
                    }
                    Text("openCoder（开放码农）：轻量级文本 / 代码编辑器，支持 SFTP 远程编辑与 SSH 命令执行。")
                        .font(DSFonts.sm)
                        .foregroundColor(DSColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, -14)
                }
                .padding(DSSpace.base)
            }
            .background(DSColors.background)
            .navigationTitle("设置")
            .confirmationDialog("断开所有服务器连接？", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
                Button("断开", role: .destructive) {
                    Task {
                        await SSHManager.shared.disconnectAll()
                        ToastCenter.shared.show(String(localized: "已断开所有连接"))
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

/// 等宽字体选择：每行带实时预览，点选即生效（终端与代码编辑器共用）。
@MainActor
struct MonoFontPickerView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        List(MonoFont.allCases) { font in
            Button {
                settings.monoFont = font
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(font.note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Ag 0123456789 $ ls -la ~/")
                            .font(font.font(size: 15))
                            .foregroundColor(.primary)
                            .padding(.top, 2)
                    }
                    Spacer()
                    if settings.monoFont == font {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("等宽字体")
        .navigationBarTitleDisplayMode(.inline)
    }
}
