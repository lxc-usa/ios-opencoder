import SwiftUI
import Runestone

/// 查找面板触发器：计数器变化时弹出系统查找导航栏。
final class FindTrigger: ObservableObject {
    @Published var counter = 0
    var showingReplace = false

    func request(replace: Bool = false) {
        showingReplace = replace
        counter += 1
    }
}

/// Runestone TextView 的 SwiftUI 封装。
@MainActor
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let language: TreeSitterLanguage
    var showLineNumbers: Bool
    var wrapLines: Bool
    var findTrigger: FindTrigger

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.showLineNumbers = showLineNumbers
        textView.isLineWrappingEnabled = wrapLines
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        // iOS 16+ 系统查找替换
        textView.isFindInteractionEnabled = true
        textView.setState(TextViewState(text: text, theme: DefaultTheme(), language: language))
        return textView
    }

    func updateUIView(_ textView: TextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        if textView.showLineNumbers != showLineNumbers {
            textView.showLineNumbers = showLineNumbers
        }
        if textView.isLineWrappingEnabled != wrapLines {
            textView.isLineWrappingEnabled = wrapLines
        }
        if context.coordinator.lastFindCounter != findTrigger.counter {
            context.coordinator.lastFindCounter = findTrigger.counter
            textView.findInteraction?.presentFindNavigator(showingReplace: findTrigger.showingReplace)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TextViewDelegate {
        private let parent: CodeEditor
        var lastFindCounter = 0

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: TextView) {
            let newText = textView.text
            if parent.text != newText {
                parent.text = newText
            }
        }
    }
}
