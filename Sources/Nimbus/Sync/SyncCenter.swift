import AppKit
import Darwin

/// A countdown that was started on another device (an iPhone Shortcut wrote a file for it).
struct RemoteTimer: Identifiable, Equatable {
    var id: String
    var device: String
    var label: String
    var start: Date
    var end: Date

    func remaining(at date: Date = Date()) -> TimeInterval { max(0, end.timeIntervalSince(date)) }

    func fraction(at date: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }
}

struct SyncConfig: Codable, Equatable {
    /// Lets Shortcuts on your devices control the Pomodoro and send messages to the island.
    var acceptCommands = true
    /// Lets your devices send updates straight to this Mac over Wi-Fi. Off until you switch it on.
    var serverEnabled = false
    var port = 8765
}

/// Watches the sync folder for files written by your other devices.
///
/// - `nimbus-command*.json`: a command to run once, then the file is deleted.
/// - `nimbus-timer*.json`: a timer running on another device, shown as a countdown.
///
/// Commands are limited to a short fixed list (Pomodoro controls and a message); nothing in a file
/// can run code or open anything.
@MainActor
final class SyncCenter: ObservableObject {
    static let shared = SyncCenter()
    private static let configKey = "nimbus.sync.config.v1"
    /// A command older than this is thrown away unrun, so a Mac that wakes up late stays calm.
    private static let commandLifetime: TimeInterval = 10 * 60

    @Published var config: SyncConfig { didSet { save() } }
    @Published private(set) var lastCommand: String?
    /// Devices that reported over Wi-Fi, by name. They are not saved: they reappear on the next update.
    @Published private(set) var networkDevices: [String: BatteryDevice] = [:]
    @Published private(set) var serverStatus = "Off"

    private let server = LocalServer()
    private var networkTimers: [String: RemoteTimer] = [:]
    private var fileTimers: [RemoteTimer] = []
    private var requestTimes: [Date] = []
    private static let tokenAccount = "sync-token"

    weak var timer: TimerStore?

    private var watcher: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    private var handled = Set<String>()
    private var announced = Set<String>()
    private var dismissed = Set<String>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(SyncConfig.self, from: data) {
            config = saved
        } else {
            config = SyncConfig()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        // NIMBUS_SERVER=1 forces the Wi-Fi link on for this run only (tests).
        if config.serverEnabled || ProcessInfo.processInfo.environment["NIMBUS_SERVER"] != nil { startServer() }
        watchFolder()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scan()
                try? await Task.sleep(for: .seconds(20)) // backstop; the watcher reacts sooner
            }
        }
    }

    func stop() {
        server.stop()
        pollTask?.cancel(); pollTask = nil
        endTask?.cancel(); endTask = nil
        watcher?.cancel(); watcher = nil
    }

    func restart() { stop(); start() }

    /// Reacts as soon as a file lands in the folder.
    private func watchFolder() {
        watcher?.cancel()
        let fd = open(SyncFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func dismiss(_ timerID: String) {
        dismissed.insert(timerID)
        scan()
    }

    // MARK: Wi-Fi link

    /// The private token every request must carry. Created the first time it is needed.
    var token: String {
        if let forced = ProcessInfo.processInfo.environment["NIMBUS_TOKEN"] { return forced } // tests only
        if let saved = KeychainStore.read(Self.tokenAccount), saved.count >= 16 { return saved }
        return regenerateToken()
    }

    @discardableResult
    func regenerateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let fresh = bytes.map { String(format: "%02x", $0) }.joined()
        KeychainStore.write(fresh, account: Self.tokenAccount)
        objectWillChange.send()
        return fresh
    }

    /// Where your devices should send requests, e.g. `http://My-Mac.local:8765`.
    var serverAddress: String { "http://\(ProcessInfo.processInfo.hostName):\(config.port)" }

    /// This Mac's address on the local network, for networks that don't resolve `.local` names.
    var lanAddress: String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            if String(cString: ifa.pointee.ifa_name) == "en0",
               let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return "http://\(String(cString: host)):\(config.port)"
                }
            }
            cursor = ifa.pointee.ifa_next
        }
        return nil
    }

    func setServer(enabled: Bool) {
        config.serverEnabled = enabled
        enabled ? startServer() : stopServer()
    }

    private func startServer() {
        _ = token // make sure one exists before anything can connect
        server.onState = { [weak self] text in Task { @MainActor in self?.serverStatus = text } }
        server.handler = { [weak self] request in
            guard let self else { return (503, "unavailable") }
            return await MainActor.run { self.handleHTTP(request) }
        }
        server.start(port: UInt16(clamping: config.port))
    }

    private func stopServer() {
        server.stop()
        serverStatus = "Off"
    }

    enum HTTPRoute: Equatable {
        case unauthorized, notFound, ping
        case battery(Data), timer(Data), command(Data)
    }

    /// Decides what a request is for. Pure, so it can be tested without a network.
    nonisolated static func route(_ request: HTTPRequestLine, token: String) -> HTTPRoute {
        var fields = request.query
        guard let supplied = fields.removeValue(forKey: "token"), constantTimeEqual(supplied, token) else {
            return .unauthorized
        }
        let body = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        switch request.path {
        case "/ping": return .ping
        case "/b", "/battery": return .battery(body)
        case "/t", "/timer": return .timer(body)
        case "/c", "/command": return .command(body)
        default: return .notFound
        }
    }

    /// Compares without stopping at the first difference, so timing reveals nothing about the token.
    nonisolated static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    private func handleHTTP(_ request: HTTPRequestLine) -> (status: Int, body: String) {
        // At most 60 requests a minute; a phone sends a handful.
        let now = Date()
        requestTimes = requestTimes.filter { now.timeIntervalSince($0) < 60 }
        guard requestTimes.count < 60 else { return (429, "slow down") }
        requestTimes.append(now)

        switch Self.route(request, token: token) {
        case .unauthorized: return (403, "forbidden")
        case .notFound: return (404, "not found")
        case .ping: return (200, "ok")
        case .battery(let data):
            guard let device = BatteryReader.parseSync(data, modified: now, fallbackName: "iPhone") else {
                return (400, "bad battery data")
            }
            networkDevices[device.name] = device
            return (200, "ok")
        case .timer(let data):
            let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String ?? "iPhone"
            guard let remote = Self.parseTimer(data, modified: now, fileName: "net-\(name)") else {
                return (400, "bad timer data")
            }
            networkTimers[name] = remote
            publish(fileTimers + Array(networkTimers.values), now: now)
            return (200, "ok")
        case .command(let data):
            guard config.acceptCommands else { return (403, "commands are off") }
            guard let command = Self.parseCommand(data) else { return (400, "unknown command") }
            run(command)
            return (200, "ok")
        }
    }

    // MARK: Scanning

    enum FileRole: Equatable { case command, timer, other }

    /// Commands and timers have fixed name prefixes. Battery files start `nimbus-device-`, so a
    /// device called "Command Center iPad" can't be mistaken for a command (and deleted).
    nonisolated static func role(of fileName: String) -> FileRole {
        let name = fileName.lowercased()
        if name.hasPrefix("nimbus-device-") { return .other }
        if name == "nimbus-command.json" || name.hasPrefix("nimbus-command-") { return .command }
        if name == "nimbus-timer.json" || name.hasPrefix("nimbus-timer-") { return .timer }
        return .other
    }

    func scan() {
        let folder = URL(fileURLWithPath: SyncFolder.path)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let onlyNimbus = SyncFolder.onlyNimbusFiles
        let now = Date()
        var timers: [RemoteTimer] = []

        for url in urls where url.pathExtension.lowercased() == "json" {
            let name = url.lastPathComponent.lowercased()
            if onlyNimbus && !name.hasPrefix("nimbus") { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now

            switch Self.role(of: url.lastPathComponent) {
            case .command:
                handleCommandFile(url, modified: modified, now: now)
            case .timer:
                if let data = try? Data(contentsOf: url),
                   let remote = Self.parseTimer(data, modified: modified, fileName: url.lastPathComponent) {
                    timers.append(remote)
                }
            case .other:
                break
            }
        }
        fileTimers = timers
        publish(timers + Array(networkTimers.values), now: now)
    }

    // MARK: Commands

    private func handleCommandFile(_ url: URL, modified: Date, now: Date) {
        let key = "\(url.lastPathComponent)|\(modified.timeIntervalSince1970)"
        guard !handled.contains(key) else { return }
        handled.insert(key)
        defer { try? FileManager.default.removeItem(at: url) } // consumed, so it never runs twice

        guard config.acceptCommands,
              now.timeIntervalSince(modified) <= Self.commandLifetime,
              let data = try? Data(contentsOf: url) else { return }
        run(Self.parseCommand(data))
    }

    enum Command: Equatable {
        case start(stage: PomodoroStage?, minutes: Int?)
        case pause, resume, reset, skip
        case notify(title: String, line: String, symbol: String)
    }

    nonisolated static func parseCommand(_ data: Data) -> Command? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dict = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.lowercased(), $0.value) })
        func text(_ key: String) -> String? { (dict[key] as? String)?.trimmingCharacters(in: .whitespaces) }
        func int(_ key: String) -> Int? {
            if let n = dict[key] as? NSNumber { return n.intValue }
            return (dict[key] as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        switch text("action")?.lowercased() {
        case "pomodoro.start", "pomodoro.begin":
            let stage = text("stage").flatMap { name -> PomodoroStage? in
                switch name.lowercased().filter(\.isLetter) {
                case "focus": return .focus
                case "short", "shortbreak": return .shortBreak
                case "long", "longbreak": return .longBreak
                default: return nil
                }
            }
            return .start(stage: stage, minutes: int("minutes"))
        case "pomodoro.pause": return .pause
        case "pomodoro.resume": return .resume
        case "pomodoro.reset": return .reset
        case "pomodoro.skip": return .skip
        case "notify":
            let title = String((text("title") ?? "Message").prefix(60))
            let line = String((text("line") ?? text("message") ?? "").prefix(120))
            return .notify(title: title, line: line, symbol: "iphone")
        default: return nil
        }
    }

    private func run(_ command: Command?) {
        guard let command else { return }
        switch command {
        case .start(let stage, let minutes): timer?.remoteStart(stage: stage, minutes: minutes)
        case .pause: timer?.pause()
        case .resume: if timer?.phase == .paused { timer?.start() }
        case .reset: timer?.reset()
        case .skip: timer?.skip()
        case .notify(let title, let line, let symbol):
            NotificationsStore.shared.post(symbol: symbol, title: title, line: line)
        }
        lastCommand = "\(command)"
        if case .notify = command { return }
        timer?.onRemoteCommand?()
    }

    // MARK: Remote timers

    /// `{"name": "iPhone", "label": "Focus", "minutes": 25}`. The start time is when the file was
    /// written, so the Shortcut doesn't need any date maths. An explicit `start` (ISO 8601 or a
    /// Unix time) overrides that.
    nonisolated static func parseTimer(_ data: Data, modified: Date, fileName: String) -> RemoteTimer? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dict = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.lowercased(), $0.value) })
        func number(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            return (v as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        guard let minutes = number(dict["minutes"]), minutes > 0, minutes <= 24 * 60 else { return nil }

        var start = modified
        if let seconds = number(dict["start"]), seconds > 1_000_000_000 {
            start = Date(timeIntervalSince1970: seconds)
        } else if let iso = dict["start"] as? String, let date = ISO8601DateFormatter().date(from: iso) {
            start = date
        }
        let device = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone"
        let label = (dict["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Timer"
        return RemoteTimer(
            id: "\(fileName)|\(start.timeIntervalSince1970)", device: device, label: label,
            start: start, end: start.addingTimeInterval(minutes * 60)
        )
    }

    private func publish(_ timers: [RemoteTimer], now: Date) {
        // Finished timers announce themselves once, then disappear.
        for remote in timers where remote.end <= now && now.timeIntervalSince(remote.end) < 120 && !announced.contains(remote.id) {
            announced.insert(remote.id)
            if !dismissed.contains(remote.id) {
                (NSSound(named: "Glass"))?.play()
                NotificationsStore.shared.post(
                    symbol: "timer", title: "\(remote.device) timer finished", line: remote.label
                )
            }
        }
        let active = timers
            .filter { $0.end > now && !dismissed.contains($0.id) }
            .min { $0.end < $1.end }
        timer?.setRemote(active)

        // Wake up exactly when the running one ends, instead of waiting for the next scan.
        endTask?.cancel()
        if let active {
            let wait = active.end.timeIntervalSince(now) + 0.3
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.scan()
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
