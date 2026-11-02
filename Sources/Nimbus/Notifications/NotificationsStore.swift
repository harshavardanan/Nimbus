import Foundation

struct NoteItem: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var line: String
    var date = Date()
}

/// Nimbus's own events (calendar reminders, timer, low battery). macOS has no public
/// API for reading other apps' notifications, so this does not try to.
@MainActor
final class NotificationsStore: ObservableObject {
    static let shared = NotificationsStore()

    @Published private(set) var items: [NoteItem] = []
    /// The note currently shown as a banner, cleared after a few seconds.
    @Published private(set) var banner: NoteItem?

    /// Set by the widget: pops the island open for a banner.
    var onBanner: ((Double) -> Void)?
    private var clearTask: Task<Void, Never>?

    func post(symbol: String, title: String, line: String, showBanner: Bool = true) {
        let note = NoteItem(symbol: symbol, title: title, line: line)
        items.insert(note, at: 0)
        if items.count > 10 { items.removeLast(items.count - 10) }
        guard showBanner else { return }

        banner = note
        onBanner?(4.5)
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.6))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func clear() {
        items.removeAll()
        banner = nil
    }

    func loadDemo() {
        items = [
            NoteItem(symbol: "timer", title: "Focus complete", line: "Time for a 5 minute break", date: Date().addingTimeInterval(-120)),
            NoteItem(symbol: "calendar", title: "Design review in 5 min", line: "Room 4", date: Date().addingTimeInterval(-900)),
            NoteItem(symbol: "battery.25", title: "Mouse battery low", line: "20% left", date: Date().addingTimeInterval(-3600)),
        ]
    }
}
