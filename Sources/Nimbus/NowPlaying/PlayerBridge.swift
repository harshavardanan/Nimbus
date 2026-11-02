import AppKit

enum PlayerApp: CaseIterable {
    case music
    case spotify

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var scriptName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    /// Checked before every script so we never launch a player by talking to it.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct PlayerSnapshot: Equatable {
    var app: PlayerApp
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var position: TimeInterval
    var duration: TimeInterval
    var artworkURL: URL?
}

/// Talks to Music and Spotify over AppleScript. macOS asks the user for
/// Automation permission the first time each player is queried.
enum PlayerBridge {
    private static let queue = DispatchQueue(label: "nimbus.applescript")
    static let musicArtworkPath = NSTemporaryDirectory() + "nimbus-artwork.bin"

    static func snapshot(of app: PlayerApp) async -> PlayerSnapshot? {
        await withCheckedContinuation { continuation in
            queue.async {
                let raw = execute(snapshotSource(app))
                continuation.resume(returning: raw.flatMap { parse($0, app: app) })
            }
        }
    }

    static func send(_ command: String, to app: PlayerApp) {
        queue.async { _ = execute("tell application \"\(app.scriptName)\" to \(command)") }
    }

    /// Music only exposes artwork as raw data, so it is written to a temp file.
    static func exportMusicArtwork() async -> NSImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                let path = musicArtworkPath
                let source = """
                tell application "Music"
                    try
                        set a to data of artwork 1 of current track
                        set f to open for access POSIX file "\(path)" with write permission
                        set eof f to 0
                        write a to f
                        close access f
                        return "ok"
                    on error
                        try
                            close access POSIX file "\(path)"
                        end try
                        return "none"
                    end try
                end tell
                """
                let image = execute(source) == "ok" ? NSImage(contentsOfFile: path) : nil
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Internals

    private static func execute(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    private static func snapshotSource(_ app: PlayerApp) -> String {
        switch app {
        case .music:
            return """
            tell application "Music"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((player position * 1000) as integer) & tab & (((duration of t) * 1000) as integer)
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((player position * 1000) as integer) & tab & (duration of t) & tab & (artwork url of t)
            end tell
            """
        }
    }

    static func parse(_ raw: String, app: PlayerApp) -> PlayerSnapshot? {
        let f = raw.components(separatedBy: "\t")
        guard f.count >= 6,
              let positionMs = Double(f[4]),
              let durationMs = Double(f[5])
        else { return nil }

        return PlayerSnapshot(
            app: app,
            isPlaying: f[0] == "playing",
            title: f[1],
            artist: f[2],
            album: f[3],
            position: positionMs / 1000,
            duration: durationMs / 1000,
            artworkURL: f.count > 6 ? URL(string: f[6]) : nil
        )
    }
}
