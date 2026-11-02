import SwiftUI

private struct WidgetAppearedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True once a widget's expanded view has been on screen for a moment; drives `reveal`.
    var widgetAppeared: Bool {
        get { self[WidgetAppearedKey.self] }
        set { self[WidgetAppearedKey.self] = newValue }
    }
}

private struct RevealModifier: ViewModifier {
    let index: Int
    @Environment(\.widgetAppeared) private var appeared
    @Environment(\.islandTheme) private var theme

    func body(content: Content) -> some View {
        content.staggered(appeared, index: index, enabled: theme.staggerContent)
    }
}

extension View {
    /// Fades and lifts a section in; higher `index` appears later.
    func reveal(_ index: Int) -> some View { modifier(RevealModifier(index: index)) }
}

/// Common layout for an expanded widget: a small heading, then content, inset below the notch.
struct WidgetFrame<Content: View>: View {
    let headline: String
    var headlineColor: Color?
    let topInset: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.islandTheme) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(headlineColor ?? theme.text.opacity(0.6))
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: headline)
                .reveal(0)
            content
        }
        .padding(.top, topInset + 2)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.widgetAppeared, appeared)
        .onAppear { appeared = true }
    }
}

/// A small tinted card used by several widgets.
struct InfoTile<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.islandTheme) private var theme

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.text.opacity(0.08)))
    }
}

/// Message with an optional action button, for empty and permission states.
struct WidgetMessage: View {
    let symbol: String
    let text: String
    var buttonTitle: String?
    var action: (() -> Void)?
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(theme.text.opacity(0.6))
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let buttonTitle, let action {
                    Button(buttonTitle, action: action)
                        .buttonStyle(PressableStyle())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.onText)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(theme.text))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// "now", "7m", "3h", "2d": a short age that keeps itself up to date.
struct ShortAge: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Text(Self.text(since: date, now: context.date))
        }
    }

    static func text(since date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(1, seconds / 60))m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
