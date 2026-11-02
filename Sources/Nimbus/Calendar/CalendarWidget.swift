import Combine
import SwiftUI

@MainActor
final class CalendarWidget: IslandWidget {
    let store = CalendarStore()

    let id = "calendar"
    let title = "Calendar"
    let subtitle = "Next event, with a countdown"
    let symbol = "calendar"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    init() {
        store.onStartingSoon = { event in
            NotificationsStore.shared.post(
                symbol: "calendar", title: "\(event.title) starts in 5 min",
                line: event.location ?? event.start.formatted(date: .omitted, time: .shortened)
            )
        }
    }

    /// Takes the compact island in the last 15 minutes before an event.
    var compactPriority: Int? { store.minutesUntilNext() != nil ? 60 : nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func start() { store.start() }
    func stop() { store.stop() }
    func loadDemo() { store.loadDemo() }

    func compactView(settings: IslandSettings) -> AnyView { AnyView(CalendarCompactView(store: store)) }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(CalendarExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 138))
    }
}

private let calendarBlue = Color(red: 0.38, green: 0.65, blue: 0.98)

private func untilText(_ start: Date, end: Date, now: Date) -> String {
    if start <= now { return "Now" }
    let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
    if minutes < 60 { return "in \(minutes) min" }
    let hours = minutes / 60
    return minutes % 60 == 0 ? "in \(hours) h" : "in \(hours) h \(minutes % 60) min"
}

struct CalendarCompactView: View {
    @ObservedObject var store: CalendarStore

    var body: some View {
        HStack {
            Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(calendarBlue)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(store.minutesUntilNext(context.date).map { "in \($0)m" } ?? "now")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(calendarBlue)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }
}

struct CalendarExpandedView: View {
    @ObservedObject var store: CalendarStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: "Next event", topInset: topInset) {
            switch store.access {
            case .unknown:
                WidgetMessage(symbol: "calendar.badge.clock",
                              text: "Nimbus needs permission to read your calendar. It only looks at upcoming events.",
                              buttonTitle: "Allow calendar access", action: store.requestAccess)
            case .denied:
                WidgetMessage(symbol: "lock.fill",
                              text: "Calendar access is off. Turn it on for Nimbus in Privacy settings.",
                              buttonTitle: "Open Privacy settings", action: store.openPrivacySettings)
            case .granted:
                if let next = store.events.first { eventView(next) }
                else { WidgetMessage(symbol: "checkmark.circle", text: "Nothing scheduled for the next day and a half.") }
            }
        }
    }

    private func eventView(_ next: EventInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                HStack(spacing: 12) {
                    Capsule().fill(next.color).frame(width: 4, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(detail(next)).font(.system(size: 12)).foregroundStyle(theme.text.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(untilText(next.start, end: next.end, now: context.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(calendarBlue))
                        .contentTransition(.numericText())
                }
            }
            .reveal(1)

            if store.events.count > 1 {
                let then = store.events[1]
                Text("Then: \(then.title) at \(then.start.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text.opacity(0.65))
                    .lineLimit(1)
                    .padding(.leading, 16)
                    .reveal(2)
            }
        }
    }

    private func detail(_ e: EventInfo) -> String {
        let range = "\(e.start.formatted(date: .omitted, time: .shortened)) to \(e.end.formatted(date: .omitted, time: .shortened))"
        return e.location.map { "\(range)  ·  \($0)" } ?? range
    }
}
