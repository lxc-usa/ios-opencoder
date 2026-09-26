import SwiftUI

// MARK: - 设计令牌（借鉴 ChunUI 思路的轻量实现）
//
// 只取三样：语义化颜色、三梯度字号、间距。不引入第三方依赖，
// 全部基于系统颜色，自动适配深色模式。

/// 语义化颜色。
enum DSColors {
    static let background: Color = Color(.systemGroupedBackground)
    static let card: Color = Color(.secondarySystemGroupedBackground)
    static let panel: Color = Color(.secondarySystemBackground)
    static let foreground: Color = .primary
    static let muted: Color = .secondary
    static let accent: Color = .accentColor
    static let border: Color = Color(.separator)
    static let destructive: Color = .red
    static let success: Color = .green
}

/// 三梯度字号。
enum DSFonts {
    static let sm: Font = .system(size: 13)
    static let smBold: Font = .system(size: 13, weight: .semibold)
    static let base: Font = .system(size: 17)
    static let baseBold: Font = .system(size: 17, weight: .semibold)
    static let lg: Font = .system(size: 24, weight: .bold)
}

/// 间距 / 圆角。
enum DSSpace {
    static let sm: CGFloat = 8
    static let base: CGFloat = 16
    static let hairline: CGFloat = 0.5
    static let radius: CGFloat = 12
    static let radiusSM: CGFloat = 8
}

// MARK: - 设置行

/// iOS 设置风格的行：圆角图标 + 标题 + 右侧自定义内容。
@MainActor
struct SettingRow<Trailing: View>: View {
    let icon: String
    let iconTint: Color
    let title: LocalizedStringKey
    let titleColor: Color
    @ViewBuilder let trailing: () -> Trailing

    init(
        icon: String,
        iconTint: Color = DSColors.accent,
        title: LocalizedStringKey,
        titleColor: Color = DSColors.foreground,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.titleColor = titleColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconTint)
                .cornerRadius(7)
            Text(title)
                .font(DSFonts.base)
                .foregroundColor(titleColor)
            Spacer()
            trailing()
        }
        .padding(.horizontal, DSSpace.base)
        .padding(.vertical, 10)
    }
}

extension SettingRow where Trailing == Text {
    /// 纯展示行：右侧为次要文字。
    init(icon: String, iconTint: Color = DSColors.accent, title: String, value: String) {
        self.init(icon: icon, iconTint: iconTint, title: title) {
            Text(value)
                .font(DSFonts.base)
                .foregroundColor(DSColors.muted)
        }
    }
}

extension SettingRow where Trailing == AnyView {
    /// 导航行：右侧为 chevron。
    init(icon: String, iconTint: Color = DSColors.accent, title: LocalizedStringKey) {
        self.init(icon: icon, iconTint: iconTint, title: title) {
            AnyView(
                Image(systemName: "chevron.right")
                    .font(DSFonts.smBold)
                    .foregroundColor(DSColors.muted)
            )
        }
    }
}

/// 行之间的 hairline 分隔线（与图标左对齐）。
@MainActor
struct SettingDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, DSSpace.base + 28 + 12)
    }
}

// MARK: - 分组卡片

/// 带标题的分组卡片，替代 Form 的 Section。
@MainActor
struct DSGroupCard<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(DSFonts.sm)
                    .foregroundColor(DSColors.muted)
                    .padding(.horizontal, DSSpace.base)
            }
            VStack(spacing: 0) {
                content
            }
            .background(DSColors.card)
            .cornerRadius(DSSpace.radius)
        }
    }
}

// MARK: - 统一空态

/// 全 App 统一的空状态：图标 + 标题 + 说明 + 可选操作按钮。
@MainActor
struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(DSColors.muted)
            Text(title)
                .font(DSFonts.baseBold)
                .foregroundColor(DSColors.foreground)
            if let message = message {
                Text(message)
                    .font(DSFonts.sm)
                    .foregroundColor(DSColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let actionTitle = actionTitle {
                Button(actionTitle) { action?() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 轻量 Toast

/// 顶部轻提示：成功类反馈用 toast，错误仍用 alert，破坏性操作仍用确认框。
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var message: String?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, duration: Duration = .seconds(2)) {
        dismissTask?.cancel()
        self.message = message
        dismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}

@MainActor
private struct ToastOverlay: ViewModifier {
    @ObservedObject var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = center.message {
                    Text(message)
                        .font(DSFonts.smBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: center.message)
    }
}

extension View {
    /// 在视图顶部叠加全局 toast。挂在根视图上即可。
    func dsToast() -> some View {
        modifier(ToastOverlay())
    }
}
