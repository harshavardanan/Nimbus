import AppKit
import EventKit
import SwiftUI

struct EventInfo: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var color: Color
}

@MainActor
final class CalendarStore: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access = Access.unknown
    @Published private(set) var events: [EventInfo] = []

    private let store = EKEventStore()
    private var pollTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var warned = Set<String>()
    private var isDemo = false

    /// Fires once per event, five minutes before it starts.
    var onStartingSoon: ((EventInfo) -> Void)?

    // MARK: Lifecycle

    func start() {
        guard !isDemo else { return }
        updateAccess()
        guard access == .granted, pollTask == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Triggers the macOS permission prompt. Only called from the button in the widget.
    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            start()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    // MARK: Events

    private func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: nil
        )
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map {
                EventInfo(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Untitled",
                    start: $0.startDate, end: $0.endDate,
                    location: $0.location?.isEmpty == false ? $0.location : nil,
                    color: Color(nsColor: $0.calendar.color ?? .systemBlue)
                )
            }
        warnIfStartingSoon(now)
    }

    private func warnIfStartingSoon(_ now: Date) {
        guard let next = events.first else { return }
        let until = next.start.timeIntervalSince(now)
        if until > 0, until <= 5 * 60, !warned.contains(next.id) {
            warned.insert(next.id)
            onStartingSoon?(next)
        }
    }

    /// Minutes until the next event starts, only when it is close enough for the compact island.
    func minutesUntilNext(_ now: Date = Date()) -> Int? {
        guard let next = events.first else { return nil }
        let until = next.start.timeIntervalSince(now)
        guard until > 0, until <= 15 * 60 else { return nil }
        return Int(ceil(until / 60))
    }

    func loadDemo() {
        isDemo = true
        access = .granted
        let now = Date()
        events = [
            EventInfo(id: "1", title: "Design review", start: now.addingTimeInterval(12 * 60),
                      end: now.addingTimeInterval(42 * 60), location: "Room 4", color: .blue),
            EventInfo(id: "2", title: "Lunch with Sam", start: now.addingTimeInterval(95 * 60),
                      end: now.addingTimeInterval(155 * 60), location: nil, color: .green),
        ]
    }
}
