import AppKit

enum PomodoroStage: String {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var isBreak: Bool { self != .focus }
}

struct PomodoroConfig: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var sessionsBeforeLongBreak = 4
    var autoStartNext = true
    var playSound = true
}

/// Pomodoro cycle: focus, short break, focus, short break ... then a long break
/// after `sessionsBeforeLongBreak` focus sessions.
@MainActor
final class TimerStore: ObservableObject {
    enum Phase { case idle, running, paused }

    static let minutesRange = 1...120
    private static let configKey = "nimbus.pomodoro.config.v1"

    @Published private(set) var stage = PomodoroStage.focus
    @Published private(set) var phase = Phase.idle
    /// Focus sessions finished in the current cycle (0 up to `sessionsBeforeLongBreak`).
    @Published private(set) var completedInCycle = 0
    /// Short message shown for a few seconds when a stage ends.
    @Published private(set) var banner: String?
    @Published var config: PomodoroConfig { didSet { save() } }

    /// A countdown running on another device (an iPhone Shortcut), if any.
    @Published private(set) var remote: RemoteTimer?

    var onFinish: (() -> Void)?
    /// Fires after a command from another device changed this timer, so the island can show it.
    var onRemoteCommand: (() -> Void)?

    private var endDate = Date()
    private var pausedRemaining: TimeInterval = 0
    private var finishTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(PomodoroConfig.self, from: data) {
            config = saved
        } else {
            config = PomodoroConfig()
        }
    }

    // MARK: Derived

    func minutes(for stage: PomodoroStage) -> Int {
        switch stage {
        case .focus: return config.focusMinutes
        case .shortBreak: return config.shortBreakMinutes
        case .longBreak: return config.longBreakMinutes
        }
    }

    /// Quick picks shown under the dial for each stage.
    func presets(for stage: PomodoroStage) -> [Int] {
        switch stage {
        case .focus: return [15, 25, 45]
        case .shortBreak: return [3, 5, 10]
        case .longBreak: return [10, 15, 30]
        }
    }

    var selectedMinutes: Int { minutes(for: stage) }
    var totalSeconds: TimeInterval { TimeInterval(selectedMinutes * 60) }
    var isLive: Bool { phase != .idle }
    /// The length can be dragged only while nothing is counting down.
    var isEditable: Bool { phase == .idle }

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle: return totalSeconds
        case .running: return max(0, endDate.timeIntervalSince(date))
        case .paused: return pausedRemaining
        }
    }

    /// 0 at the start of the stage, 1 when the time is up.
    func elapsedFraction(at date: Date = Date()) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(1 - remaining(at: date) / totalSeconds, 0), 1)
    }

    // MARK: Controls

    func start() {
        let seconds = phase == .paused ? pausedRemaining : totalSeconds
        endDate = Date().addingTimeInterval(seconds)
        phase = .running
        schedule(after: seconds)
    }

    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining()
        finishTask?.cancel()
        phase = .paused
    }

    /// Back to the start of the current stage.
    func reset() {
        finishTask?.cancel()
        phase = .idle
    }

    /// Jump to the next stage without counting this one as done.
    func skip() {
        finishTask?.cancel()
        phase = .idle
        banner = nil
        switch stage {
        case .focus: stage = .shortBreak
        case .shortBreak: stage = .focus
        case .longBreak:
            completedInCycle = 0
            stage = .focus
        }
    }

    /// Start the whole cycle again from the first focus session.
    func restartCycle() {
        finishTask?.cancel()
        phase = .idle
        banner = nil
        completedInCycle = 0
        stage = .focus
    }

    /// Sets the length of the current stage. Ignored while a countdown is active.
    func setMinutes(_ minutes: Int) {
        guard isEditable else { return }
        select(minutes: minutes)
    }

    func select(minutes: Int) {
        let clamped = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
        switch stage {
        case .focus: config.focusMinutes = clamped
        case .shortBreak: config.shortBreakMinutes = clamped
        case .longBreak: config.longBreakMinutes = clamped
        }
        reset()
    }

    func setRemote(_ timer: RemoteTimer?) {
        if remote != timer { remote = timer }
    }

    /// Starts a stage on request from another device. A length, if given, becomes that stage's length.
    func remoteStart(stage: PomodoroStage?, minutes: Int?) {
        finishTask?.cancel()
        phase = .idle
        banner = nil
        if let stage { self.stage = stage }
        if let minutes {
            let clamped = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
            switch self.stage {
            case .focus: config.focusMinutes = clamped
            case .shortBreak: config.shortBreakMinutes = clamped
            case .longBreak: config.longBreakMinutes = clamped
            }
        }
        start()
    }

    /// Screenshot helper: two sessions done, 24:32 left of the third.
    func loadDemo() {
        stage = .focus
        completedInCycle = 2
        endDate = Date().addingTimeInterval(24 * 60 + 32)
        phase = .running
    }

    // MARK: Finishing

    private func schedule(after seconds: TimeInterval) {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        let finished = stage
        let next: PomodoroStage
        switch finished {
        case .focus:
            completedInCycle += 1
            next = completedInCycle >= config.sessionsBeforeLongBreak ? .longBreak : .shortBreak
            setBanner(next == .longBreak
                ? "Cycle complete. Take a long break."
                : "Focus complete. \(minutes(for: next)) min break.")
        case .shortBreak:
            next = .focus
            setBanner("Break over. Back to focus.")
        case .longBreak:
            completedInCycle = 0
            next = .focus
            setBanner("Fresh start. Ready to focus.")
        }

        stage = next
        phase = .idle
        if config.playSound {
            (NSSound(named: finished == .focus ? "Glass" : "Hero") ?? NSSound(named: "Ping"))?.play()
        }
        if config.autoStartNext { start() }
        onFinish?()
    }

    private func setBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
