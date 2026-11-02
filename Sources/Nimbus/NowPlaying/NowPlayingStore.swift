import AppKit
import SwiftUI

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var app: PlayerApp

    var id: String { "\(title)|\(artist)|\(album)" }
}

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Color(red: 1.0, green: 0.48, blue: 0.35)

    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isDemo = false
    private let isEnvDemo = ProcessInfo.processInfo.environment["NIMBUS_DEMO"] != nil

    /// Used by the settings preview so every mode can be shown with nothing playing.
    func setDemo(_ on: Bool) {
        if on {
            if !isDemo { loadDemo() }
        } else if isDemo && !isEnvDemo {
            isDemo = false
            track = nil
            isPlaying = false
            artwork = nil
        }
    }

    /// Fixed fake track for screenshots and design review (`NIMBUS_DEMO=1`).
    func loadDemo() {
        isDemo = true
        track = Track(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                      duration: 241, app: .music)
        isPlaying = true
        anchorPosition = 84
        anchorDate = Date()
        accent = Color(red: 1.0, green: 0.48, blue: 0.35)
    }

    func start() {
        guard pollTask == nil else { return }
        if ProcessInfo.processInfo.environment["NIMBUS_DEMO"] != nil { loadDemo(); return }
        // Music and Spotify announce every play, pause and track change, so there is no need to
        // ask them constantly. The announcements wake us; the poll below is only a backstop.
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Progress is interpolated locally, so asking every few seconds is plenty.
                let idle = self?.isPlaying == false
                try? await Task.sleep(for: .seconds(idle ? 15 : 5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    /// Position is interpolated between polls so the progress bar moves smoothly.
    func position(at date: Date) -> TimeInterval {
        isPlaying ? anchorPosition + date.timeIntervalSince(anchorDate) : anchorPosition
    }

    // MARK: Transport

    func togglePlayPause() {
        guard let app = track?.app else { return }
        anchorPosition = position(at: Date())
        anchorDate = Date()
        isPlaying.toggle()
        PlayerBridge.send("playpause", to: app)
        refreshSoon()
    }

    /// Jump to `time` seconds. The local clock moves immediately so the bar
    /// doesn't snap back while the player catches up.
    func seek(to time: TimeInterval) {
        guard let track else { return }
        let target = min(max(0, time), track.duration)
        anchorPosition = target
        anchorDate = Date()
        guard !isDemo else { return }
        PlayerBridge.send("set player position to \(Int(target))", to: track.app)
        refreshSoon()
    }

    func next() {
        guard let app = track?.app else { return }
        PlayerBridge.send("next track", to: app)
        refreshSoon()
    }

    func previous() {
        guard let app = track?.app else { return }
        PlayerBridge.send("previous track", to: app)
        refreshSoon()
    }

    // MARK: Polling

    /// Several announcements can arrive together (state, position, track), so they are merged.
    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        var best: PlayerSnapshot?
        for app in PlayerApp.allCases where app.isRunning {
            guard let snapshot = await PlayerBridge.snapshot(of: app) else { continue }
            if snapshot.isPlaying { best = snapshot; break }
            if best == nil { best = snapshot }
        }
        apply(best)
    }

    private func apply(_ snapshot: PlayerSnapshot?) {
        guard !isDemo else { return }
        guard let snapshot else {
            track = nil
            isPlaying = false
            artwork = nil
            return
        }

        let incoming = Track(
            title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
            duration: snapshot.duration, app: snapshot.app
        )
        let changed = incoming.id != track?.id
        track = incoming
        isPlaying = snapshot.isPlaying
        anchorPosition = snapshot.position
        anchorDate = Date()

        if changed { loadArtwork(for: snapshot, trackID: incoming.id) }
    }

    private func loadArtwork(for snapshot: PlayerSnapshot, trackID: String) {
        artwork = nil
        Task { [weak self] in
            let image: NSImage?
            switch snapshot.app {
            case .music:
                image = await PlayerBridge.exportMusicArtwork()
            case .spotify:
                if let url = snapshot.artworkURL, let (data, _) = try? await URLSession.shared.data(from: url) {
                    image = NSImage(data: data)
                } else {
                    image = nil
                }
            }
            guard let self, self.track?.id == trackID else { return } // track changed meanwhile
            self.artwork = image
            if let color = image?.averageColor() { self.accent = Color(nsColor: color) }
        }
    }
}

extension NSImage {
    /// Average colour, pushed towards a bright, saturated tone so it reads on black.
    func averageColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let base = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        base.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return NSColor(hue: h, saturation: max(s, 0.5), brightness: max(b, 0.85), alpha: 1)
    }
}
