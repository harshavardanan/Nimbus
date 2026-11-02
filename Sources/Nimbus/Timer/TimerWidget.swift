import AppKit
import Combine
import SwiftUI

@MainActor
final class TimerWidget: IslandWidget {
    let store = TimerStore()

    let id = "timer"
    let title = "Pomodoro"
    let subtitle = "Focus and break cycles"
    let symbol = "timer"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    init() {
        store.onFinish = { [weak self] in self?.requestPeek?(5) }
        store.onRemoteCommand = { [weak self] in self?.requestPeek?(3) }
        SyncCenter.shared.timer = store
    }

    func loadDemo() {
        if ProcessInfo.processInfo.environment["NIMBUS_TIMER"] != "idle" { store.loadDemo() }
    }

    /// Your own countdown wins; a timer running on your phone comes next.
    var compactPriority: Int? { store.isLive ? 80 : (store.remote != nil ? 75 : nil) }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func compactView(settings: IslandSettings) -> AnyView {
        AnyView(TimerCompactSwitch(store: store))
    }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(TimerExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }
}

// MARK: Shared bits

private let focusTint = Color(red: 1.0, green: 0.42, blue: 0.38)
private let breakTint = Color(red: 0.42, green: 0.86, blue: 0.58)

private func stageColor(_ stage: PomodoroStage) -> Color { stage.isBreak ? breakTint : focusTint }

private func formatTime(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(ceil(seconds)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// One dot per focus session in the cycle: filled when done, pulsing for the current one.
private struct SessionDots: View {
    let total: Int
    let done: Int
    let current: Bool
    let tint: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                let isDone = i < done
                let isCurrent = current && i == done
                Circle()
                    .fill(isDone ? tint : Color.clear)
                    .overlay(Circle().stroke(isDone ? tint : tint.opacity(isCurrent ? 1 : 0.4), lineWidth: 1.2))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isCurrent && pulse ? 1.25 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isDone)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total) focus sessions done")
    }
}

// MARK: Remote (timer running on another device)

private let remoteBlue = Color(red: 0.38, green: 0.65, blue: 0.98)

struct TimerCompactSwitch: View {
    @ObservedObject var store: TimerStore

    var body: some View {
        if store.isLive || store.remote == nil {
            TimerCompactView(store: store)
        } else if let remote = store.remote {
            HStack {
                Image(systemName: "iphone").font(.system(size: 11, weight: .semibold)).foregroundStyle(remoteBlue)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(formatTime(remote.remaining(at: context.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(remoteBlue)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
    }
}

struct RemoteTimerView: View {
    let remote: RemoteTimer
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: "On \(remote.device) · \(remote.label)", headlineColor: remoteBlue, topInset: topInset) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = remote.remaining(at: context.date)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text(formatTime(remaining))
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy(duration: 0.22), value: Int(ceil(remaining)))
                        Spacer()
                        Button("Dismiss") { SyncCenter.shared.dismiss(remote.id) }
                            .buttonStyle(PressableStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(theme.text.opacity(0.12)))
                    }
                    .reveal(1)
                    Capsule().fill(theme.text.opacity(0.2)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(remoteBlue)
                                    .frame(width: geo.size.width * remote.fraction(at: context.date))
                                    .animation(.linear(duration: 0.25), value: remote.fraction(at: context.date))
                            }
                        }
                        .reveal(2)
                }
            }
        }
    }
}

// MARK: Compact

struct TimerCompactView: View {
    @ObservedObject var store: TimerStore
    @State private var pulse = false

    var body: some View {
        let color = stageColor(store.stage)
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(store.phase == .running ? (pulse ? 1 : 0.35) : 1)
                Text(store.phase == .paused ? "Paused" : store.stage.isBreak ? "Break" : "Focus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(formatTime(store.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.4), value: store.stage)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: Expanded

struct TimerExpandedView: View {
    @ObservedObject var store: TimerStore
    let topInset: CGFloat

    @Environment(\.islandTheme) private var theme
    @State private var appeared = false
    @State private var resetTaps = 0
    @State private var skipTaps = 0
    @State private var isDragging = false
    @State private var rising = false
    @State private var dragBase: Int?

    var body: some View {
        if let remote = store.remote, store.phase == .idle {
            RemoteTimerView(remote: remote, topInset: topInset)
        } else {
            localBody
        }
    }

    @ViewBuilder
    private var localBody: some View {
        let color = stageColor(store.stage)
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(headline)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        SessionDots(
                            total: store.config.sessionsBeforeLongBreak,
                            done: store.completedInCycle,
                            current: store.stage == .focus,
                            tint: focusTint
                        )
                    }
                    .animation(.smooth(duration: 0.3), value: headline)

                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let remaining = store.remaining(at: context.date)
                        Text(formatTime(remaining))
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText(countsDown: !rising))
                            .animation(.snappy(duration: 0.22), value: Int(ceil(remaining)))
                    }
                    .scaleEffect(isDragging ? 1.07 : 1, anchor: .leading)
                    .shadow(color: color.opacity(isDragging ? 0.5 : 0), radius: 12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
                    .contentShape(Rectangle())
                    .gesture(timeDrag)
                    .help(store.isEditable ? "Drag sideways to set the time" : "")
                }
                .staggered(appeared, index: 0, enabled: theme.staggerContent)

                Spacer()

                HStack(spacing: 8) {
                    roundButton(primarySymbol, label: primaryLabel, size: 40, tint: color, prominent: true) {
                        store.phase == .running ? store.pause() : store.start()
                    }
                    roundButton("arrow.counterclockwise", label: "Reset this stage", size: 34, tint: color, prominent: false) {
                        resetTaps += 1
                        store.reset()
                    }
                    .symbolEffect(.bounce, value: resetTaps)
                    roundButton("forward.end.fill", label: "Skip to next stage", size: 34, tint: color, prominent: false) {
                        skipTaps += 1
                        store.skip()
                    }
                    .symbolEffect(.bounce, value: skipTaps)
                }
                .staggered(appeared, index: 1, enabled: theme.staggerContent)
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                if store.isEditable { dial(color) } else { progressBar(color) }
                HStack(spacing: 6) {
                    ForEach(store.presets(for: store.stage), id: \.self) { minutes in presetChip(minutes, color) }
                }
            }
            .staggered(appeared, index: 2, enabled: theme.staggerContent)
        }
        .padding(.top, topInset + 2)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .foregroundStyle(theme.text)
        .animation(.smooth(duration: 0.4), value: store.stage)
        .onAppear { appeared = true }
    }

    // MARK: Text

    private var headline: String {
        if isDragging { return "SET \(store.stage.title.uppercased())" }
        if let banner = store.banner { return banner.uppercased() }
        return store.phase == .paused ? "PAUSED" : store.stage.title.uppercased()
    }

    private var primarySymbol: String { store.phase == .running ? "pause.fill" : "play.fill" }

    private var primaryLabel: String {
        switch store.phase {
        case .running: return "Pause"
        case .paused: return "Resume"
        case .idle: return "Start"
        }
    }

    // MARK: Progress and dial

    private func progressBar(_ color: Color) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let fraction = store.elapsedFraction(at: context.date)
            Capsule()
                .fill(theme.text.opacity(0.2))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * fraction)
                            .animation(.linear(duration: 0.25), value: fraction)
                    }
                }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    /// Dragging the time itself: about 4 points per minute, relative to where the drag began.
    private var timeDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard store.isEditable else { return }
                if dragBase == nil { dragBase = store.selectedMinutes }
                isDragging = true
                apply(minutes: (dragBase ?? store.selectedMinutes) + Int((value.translation.width / 4).rounded()))
            }
            .onEnded { _ in
                dragBase = nil
                isDragging = false
            }
    }

    /// Tick-marked dial: tap or drag anywhere on it to set 1 to 120 minutes. Ticks near the
    /// handle swell like the Dock, and the handle glows while held.
    private func dial(_ color: Color) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let range = Double(TimerStore.minutesRange.upperBound)
            let handleX = width * Double(store.selectedMinutes) / range

            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.2)).frame(height: 4)
                Capsule().fill(color).frame(width: handleX, height: 4)

                ForEach(1...Int(range / 5), id: \.self) { i in
                    let x = width * Double(i * 5) / range
                    let near = isDragging ? exp(-pow((x - handleX) / 36, 2)) : 0
                    let major = i % 3 == 0
                    let base: CGFloat = major ? 9 : 6
                    Capsule()
                        .fill(x <= handleX ? color.opacity(0.85) : theme.text.opacity(major ? 0.5 : 0.28))
                        .frame(width: 1.5, height: base + 9 * near)
                        .offset(x: x - 0.75, y: -base / 2 - 5 - 4 * near)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: near)
                }

                Circle()
                    .fill(theme.text)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isDragging ? 1.5 : 1)
                    .shadow(color: color.opacity(isDragging ? 0.9 : 0.25), radius: isDragging ? 8 : 2)
                    .offset(x: handleX - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        apply(minutes: Int((value.location.x / width * range).rounded()))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.8), value: store.selectedMinutes)
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("\(store.stage.title) length")
        .accessibilityValue("\(store.selectedMinutes) minutes")
        .accessibilityAdjustableAction { direction in
            apply(minutes: store.selectedMinutes + (direction == .increment ? 5 : -5))
        }
    }

    private func apply(minutes: Int) {
        let clamped = min(max(minutes, TimerStore.minutesRange.lowerBound), TimerStore.minutesRange.upperBound)
        guard clamped != store.selectedMinutes else { return }
        rising = clamped > store.selectedMinutes
        store.setMinutes(clamped)
        // A soft click on a trackpad each time you cross a 5 minute mark.
        if clamped % 5 == 0 {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: Buttons

    private func presetChip(_ minutes: Int, _ color: Color) -> some View {
        let selected = store.selectedMinutes == minutes
        return Button {
            rising = minutes > store.selectedMinutes
            store.select(minutes: minutes)
        } label: {
            Text("\(minutes)")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? color : theme.text.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        .accessibilityLabel("\(minutes) minutes")
    }

    private func roundButton(
        _ symbol: String, label: String, size: CGFloat, tint: Color, prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? Color.black : theme.text)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? tint : theme.text.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .animation(.smooth(duration: 0.25), value: store.phase)
        .accessibilityLabel(label)
    }
}

// MARK: Settings

/// Pomodoro options shown in the Widgets tab of the Settings window.
struct PomodoroSettingsSection: View {
    @ObservedObject var store: TimerStore

    var body: some View {
        Section("Pomodoro") {
            Stepper("Focus: \(store.config.focusMinutes) min", value: $store.config.focusMinutes, in: TimerStore.minutesRange)
            Stepper("Short break: \(store.config.shortBreakMinutes) min", value: $store.config.shortBreakMinutes, in: TimerStore.minutesRange)
            Stepper("Long break: \(store.config.longBreakMinutes) min", value: $store.config.longBreakMinutes, in: TimerStore.minutesRange)
            Stepper("Long break after \(store.config.sessionsBeforeLongBreak) focus sessions",
                    value: $store.config.sessionsBeforeLongBreak, in: 2...8)
            Toggle("Start the next stage automatically", isOn: $store.config.autoStartNext)
            Toggle("Play a sound when a stage ends", isOn: $store.config.playSound)
            Button("Restart the cycle") { store.restartCycle() }
        }
    }
}
