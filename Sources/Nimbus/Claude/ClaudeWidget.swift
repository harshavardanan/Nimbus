import AppKit
import Combine
import SwiftUI

/// Lets any widget open the Settings window without knowing about the window controller.
enum AppActions {
    static var openSettings: () -> Void = {}
}

@MainActor
final class ClaudeWidget: IslandWidget {
    let store = ClaudeStore()

    let id = "claude"
    let title = "Ask Claude"
    let subtitle = "Type a question, the answer streams in"
    let symbol = "sparkles"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    /// Stay open while you are typing or an answer is arriving.
    var holdsIslandOpen: Bool { store.fieldFocused || store.isStreaming }
    var wantsKeyboard: Bool { store.hasKey }

    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(ClaudeExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }
}

struct ClaudeExpandedView: View {
    @ObservedObject var store: ClaudeStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme
    @FocusState private var focused: Bool

    private let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        WidgetFrame(headline: headline, headlineColor: store.isStreaming ? accent : nil, topInset: topInset) {
            if store.hasKey { chat } else {
                WidgetMessage(symbol: "key.fill",
                              text: "Add your Anthropic API key in Settings. It is stored in your Keychain and only sent to api.anthropic.com when you ask something.",
                              buttonTitle: "Open Settings", action: { AppActions.openSettings() })
            }
        }
        .onChange(of: focused) { _, now in store.fieldFocused = now }
        .onKeyPress(.escape) {
            store.cancel()
            focused = false
            return .handled
        }
    }

    private var headline: String {
        if store.isStreaming { return "Claude is answering" }
        return store.errorText == nil ? "Ask Claude" : "Something went wrong"
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(accent)
                TextField("Ask anything…", text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { store.ask() }
                    .disabled(store.isStreaming)
                if store.isStreaming {
                    Button { store.cancel() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Stop")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.text.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(focused ? 0.8 : 0), lineWidth: 1.2))
            .animation(.easeOut(duration: 0.2), value: focused)
            .reveal(1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if !store.question.isEmpty {
                        Text(store.question).font(.system(size: 11)).foregroundStyle(theme.text.opacity(0.55)).lineLimit(2)
                    }
                    if let error = store.errorText {
                        Text(error).font(.system(size: 12)).foregroundStyle(Color(red: 0.97, green: 0.44, blue: 0.44))
                    } else if !store.answer.isEmpty {
                        Text(rendered + (store.isStreaming ? AttributedString(" ▍") : AttributedString()))
                            .font(.system(size: 12.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if store.question.isEmpty {
                        Text("Return to send. Esc to close.").font(.system(size: 11)).foregroundStyle(theme.text.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .reveal(2)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: store.answer, options: options)) ?? AttributedString(store.answer)
    }
}

struct ClaudeSettingsSection: View {
    @ObservedObject var store: ClaudeStore
    @State private var newKey = ""

    var body: some View {
        Section("Ask Claude") {
            if store.hasKey {
                LabeledContent("API key") { Text("Saved in Keychain").foregroundStyle(.secondary) }
                Button("Remove key", role: .destructive) { store.removeKey() }
            } else {
                SecureField("Anthropic API key", text: $newKey)
                    .onSubmit(save)
                Button("Save key", action: save).disabled(newKey.isEmpty)
            }
            TextField("Model", text: $store.config.model)
            Text("The key is stored in your macOS Keychain. It and your question are sent to api.anthropic.com only when you press Return in the island.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        store.saveKey(newKey)
        newKey = ""
    }
}
