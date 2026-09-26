import SwiftUI

/// 编辑器宿主：顶部标签页条 + Runestone 编辑器。
@MainActor
struct EditorHostView: View {
    @ObservedObject var documents: DocumentManager
    @ObservedObject var settings: SettingsStore

    @StateObject private var findTrigger = FindTrigger()
    @State private var pendingClose: OpenDocument?
    @State private var showCloseAlert = false
    @State private var saveError: String?
    @State private var showSaveError = false

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            if let doc = documents.selected {
                DocumentContentView(
                    doc: doc,
                    documents: documents,
                    settings: settings,
                    findTrigger: findTrigger,
                    onSaveError: { message in
                        saveError = message
                        showSaveError = true
                    }
                )
            } else {
                EmptyState(
                    icon: "doc.text",
                    title: "没有打开的文件",
                    message: "从「文件」或「服务器」中打开一个文件开始编辑"
                )
            }
        }
        .navigationTitle(documents.selected?.title ?? "编辑器")
        .navigationBarTitleDisplayMode(.inline)
        .alert("有未保存的更改", isPresented: $showCloseAlert) {
            Button("保存并关闭") { saveAndClose() }
            Button("直接关闭", role: .destructive) {
                if let doc = pendingClose { documents.close(doc) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("「%@」有未保存的更改，要怎么处理？", comment: ""), pendingClose?.title ?? ""))
        }
        .alert("保存失败", isPresented: $showSaveError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - 标签页条

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(documents.documents) { doc in
                        TabButton(
                            doc: doc,
                            isSelected: documents.selectedID == doc.id,
                            onSelect: { documents.selectedID = doc.id },
                            onClose: { requestClose(doc) }
                        )
                        .id(doc.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                scrollToSelectedSoon(proxy, animated: false)
            }
            .onChange(of: documents.selectedID) { _, _ in
                scrollToSelectedSoon(proxy, animated: true)
            }
        }
    }

    /// 把标签页条滚动到当前选中的标签，保证活跃文件始终可见。
    /// 用 Task 跳一拍：刚打开文件时新标签还没完成布局，直接 scrollTo 会滚不到。
    private func scrollToSelectedSoon(_ proxy: ScrollViewProxy, animated: Bool) {
        Task {
            guard let id = documents.selectedID else { return }
            if animated {
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            } else {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    // MARK: - 编辑区

/// 文档内容区：独立观察单个文档。
/// 根因说明：之前这里直接用 `editorArea(for: doc)`，doc 只是普通参数，
/// EditorHostView 只观察 DocumentManager；doc.isLoading 从 true 变 false 时
/// documents 数组本身没变，SwiftUI 不会重算该区域，界面永久卡在"加载中…"。
/// 现在由独立视图持有 @ObservedObject，状态变化即刷新。
@MainActor
private struct DocumentContentView: View {
    @ObservedObject var doc: OpenDocument
    @ObservedObject var documents: DocumentManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var findTrigger: FindTrigger
    var onSaveError: (String) -> Void

    var body: some View {
        if doc.isLoading {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = doc.loadError {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "打开失败",
                message: "\(error)",
                actionTitle: "关闭",
                action: { documents.close(doc) }
            )
        } else {
            DocEditorView(
                doc: doc,
                documents: documents,
                settings: settings,
                findTrigger: findTrigger,
                onSaveError: onSaveError
            )
        }
    }
}

    // MARK: - 关闭

    private func requestClose(_ doc: OpenDocument) {
        if doc.isDirty {
            pendingClose = doc
            showCloseAlert = true
        } else {
            documents.close(doc)
        }
    }

    private func saveAndClose() {
        guard let doc = pendingClose else { return }
        Task {
            do {
                try await documents.save(doc)
                documents.close(doc)
            } catch {
                saveError = error.localizedDescription
                showSaveError = true
            }
            pendingClose = nil
        }
    }
}

/// 单个标签页按钮。
@MainActor
private struct TabButton: View {
    @ObservedObject var doc: OpenDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    if doc.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                    }
                    Text(doc.title)
                        .lineLimit(1)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .background(isSelected ? Color(.secondarySystemGroupedBackground) : Color.clear)
        .cornerRadius(8)
    }
}

/// 绑定单个文档的编辑器视图（观察文档文本变化；工具栏放这里，保存按钮随 dirty 状态实时更新）。
@MainActor
private struct DocEditorView: View {
    @ObservedObject var doc: OpenDocument
    @ObservedObject var documents: DocumentManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var findTrigger: FindTrigger
    var onSaveError: (String) -> Void

    @State private var isSaving = false

    var body: some View {
        CodeEditor(
            text: $doc.text,
            fileExtension: doc.fileExtension,
            showLineNumbers: settings.showLineNumbers,
            wrapLines: settings.wordWrap,
            findTrigger: findTrigger,
            monoFont: settings.monoFont,
            fontSize: CGFloat(settings.monoFontSize),
            lineSpacing: CGFloat(settings.lineSpacing)
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("查找") { findTrigger.request() }
                Button("替换") { findTrigger.request(replace: true) }
                if isSaving {
                    ProgressView()
                } else {
                    Button("保存") { save() }
                        .bold()
                        .disabled(!doc.isDirty)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await documents.save(doc)
                ToastCenter.shared.show(String(localized: "已保存"))
            } catch {
                onSaveError(error.localizedDescription)
            }
            isSaving = false
        }
    }
}
