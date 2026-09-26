import SwiftUI

/// App 设置。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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

                    DSGroupCard(title: "连接") {
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
                        SettingRow(icon: "app.badge", title: "版本", value: "1.0 (1)")
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
                        ToastCenter.shared.show("已断开所有连接")
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
