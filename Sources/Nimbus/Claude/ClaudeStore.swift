import Foundation

struct ClaudeConfig: Codable, Equatable {
    var model = "claude-sonnet-5-5"
}

@MainActor
final class ClaudeStore: ObservableObject {
    private static let configKey = "nimbus.claude.config.v1"
    private static let system = """
    You are answering inside a very small panel on a Mac's notch. Keep answers short, \
    plain and direct, ideally under 80 words, unless the user asks for more.
    """

    @Published var draft = ""
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var errorText: String?
    @Published private(set) var hasKey: Bool
    /// Set by the view while the text field has keyboard focus.
    @Published var fieldFocused = false
    @Published var config: ClaudeConfig { didSet { save() } }

    private var turns: [ChatTurn] = []
    private var streamTask: Task<Void, Never>?

    init() {
        hasKey = KeychainStore.read(KeychainStore.anthropicKey) != nil
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(ClaudeConfig.self, from: data) {
            config = saved
        } else {
            config = ClaudeConfig()
        }
    }

    // MARK: Key

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.write(trimmed, account: KeychainStore.anthropicKey)
        refreshKey()
    }

    func removeKey() {
        KeychainStore.delete(KeychainStore.anthropicKey)
        newChat()
        refreshKey()
    }

    func refreshKey() { hasKey = KeychainStore.read(KeychainStore.anthropicKey) != nil }

    // MARK: Asking

    func ask() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming,
              let key = KeychainStore.read(KeychainStore.anthropicKey) else { return }

        draft = ""
        question = prompt
        answer = ""
        errorText = nil
        isStreaming = true
        turns.append(ChatTurn(role: .user, text: prompt))
        let sent = Array(turns.suffix(8)) // a short memory so follow-ups work
        let model = config.model

        streamTask = Task { [weak self] in
            do {
                for try await piece in ClaudeClient.stream(apiKey: key, model: model, system: Self.system, turns: sent) {
                    self?.answer += piece
                }
                if let self { self.turns.append(ChatTurn(role: .assistant, text: self.answer)) }
            } catch is CancellationError {
            } catch {
                self?.errorText = error.localizedDescription
                self?.turns.removeLast() // the failed question isn't part of the conversation
            }
            self?.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        isStreaming = false
    }

    func newChat() {
        cancel()
        turns.removeAll()
        question = ""
        answer = ""
        errorText = nil
    }

    func loadDemo() {
        hasKey = true
        question = "What does 0 20 * * 1 mean in cron?"
        answer = "Every Monday at 20:00 (8 pm). The five fields are minute, hour, day of month, month and day of week."
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
