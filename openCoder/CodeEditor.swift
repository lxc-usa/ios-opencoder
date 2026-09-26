import SwiftUI
import UIKit
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
    var monoFont: MonoFont
    var fontSize: CGFloat
    var lineSpacing: CGFloat

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
        // Runestone 把文本区背景写死为 .white，深色下会白字白底看不见。
        // 改成深浅自适应：浅色白、深色黑（与深色行号栏一致），trait 变化时自动重算。
        textView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
        let uiFont = monoFont.uiFont(size: fontSize)
        textView.setState(TextViewState(text: text, theme: MonoTheme(font: uiFont), language: language))
        textView.lineHeightMultiplier = Self.lineHeightMultiplier(for: uiFont, spacing: lineSpacing)
        context.coordinator.lastFontID = monoFont.id
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastLineSpacing = lineSpacing
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
        let coordinator = context.coordinator
        if coordinator.lastFontID != monoFont.id || coordinator.lastFontSize != fontSize {
            coordinator.lastFontID = monoFont.id
            coordinator.lastFontSize = fontSize
            let uiFont = monoFont.uiFont(size: fontSize)
            textView.theme = MonoTheme(font: uiFont)
            textView.lineHeightMultiplier = Self.lineHeightMultiplier(for: uiFont, spacing: lineSpacing)
            coordinator.lastLineSpacing = lineSpacing
        } else if coordinator.lastLineSpacing != lineSpacing {
            coordinator.lastLineSpacing = lineSpacing
            textView.lineHeightMultiplier = Self.lineHeightMultiplier(
                for: monoFont.uiFont(size: fontSize), spacing: lineSpacing)
        }
        if coordinator.lastFindCounter != findTrigger.counter {
            coordinator.lastFindCounter = findTrigger.counter
            textView.findInteraction?.presentFindNavigator(showingReplace: findTrigger.showingReplace)
        }
    }

    /// 把"行距（磅）"换算成 Runestone 的行高倍数。
    /// Runestone 用 theme.font.totalLineHeight（= ascender + |descender| + leading）做基准行高。
    static func lineHeightMultiplier(for font: UIFont, spacing: CGFloat) -> CGFloat {
        let base = font.ascender + abs(font.descender) + font.leading
        guard base > 0 else { return 1 }
        return (base + spacing) / base
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TextViewDelegate {
        private let parent: CodeEditor
        var lastFindCounter = 0
        var lastFontID: String?
        var lastFontSize: CGFloat = 0
        var lastLineSpacing: CGFloat = -1

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

/// 可换字体的 Runestone 主题：包装 DefaultTheme，只覆盖字体相关项，其余颜色与字重全部委托。
///
/// Runestone 的字体来自 Theme（DefaultTheme 写死 14pt 系统等宽），想换字体只能换主题。
final class MonoTheme: Theme {
    private let base = DefaultTheme()
    let font: UIFont

    init(font: UIFont) {
        self.font = font
    }

    var lineNumberFont: UIFont { font }
    var textColor: UIColor { base.textColor }
    var gutterBackgroundColor: UIColor { base.gutterBackgroundColor }
    var gutterHairlineColor: UIColor { base.gutterHairlineColor }
    var lineNumberColor: UIColor { base.lineNumberColor }
    var selectedLineBackgroundColor: UIColor { base.selectedLineBackgroundColor }
    var selectedLinesLineNumberColor: UIColor { base.selectedLinesLineNumberColor }
    var selectedLinesGutterBackgroundColor: UIColor { base.selectedLinesGutterBackgroundColor }
    var invisibleCharactersColor: UIColor { base.invisibleCharactersColor }
    var pageGuideHairlineColor: UIColor { base.pageGuideHairlineColor }
    var pageGuideBackgroundColor: UIColor { base.pageGuideBackgroundColor }
    var markedTextBackgroundColor: UIColor { base.markedTextBackgroundColor }

    func textColor(for highlightName: String) -> UIColor? {
        base.textColor(for: highlightName)
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        base.fontTraits(for: highlightName)
    }
}
