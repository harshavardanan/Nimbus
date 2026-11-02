import SwiftUI

struct NowPlayingExpandedView: View {
    @ObservedObject var store: NowPlayingStore
    /// Height of the closed island; content sits below it.
    let topInset: CGFloat

    @Environment(\.islandTheme) private var theme

    /// Non-nil while the progress bar is being dragged.
    @State private var scrubFraction: Double?
    /// Flips on first appearance so sections can reveal one after another.
    @State private var appeared = false
    @State private var previousTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        Group {
            if let track = store.track {
                nowPlaying(track)
            } else {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .staggered(appeared, index: 0, enabled: theme.staggerContent)
            }
        }
        .padding(.top, topInset + 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear { appeared = true }
    }

    // MARK: Now playing

    private func nowPlaying(_ track: Track) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(image: store.artwork, accent: theme.accent, cornerRadius: 12)
                    .frame(width: 58, height: 58)
                    .shadow(color: theme.accent.opacity(0.35), radius: 8, y: 3)
                    .id(track.id)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .staggered(appeared, index: 0, enabled: theme.staggerContent)

                VStack(alignment: .leading, spacing: 1) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text.opacity(0.65))
                            .lineLimit(1)
                    }
                    .id(track.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    ))
                    .staggered(appeared, index: 1, enabled: theme.staggerContent)

                    progress(duration: track.duration)
                        .padding(.top, 8)
                        .staggered(appeared, index: 2, enabled: theme.staggerContent)
                }
            }
            .animation(.smooth(duration: 0.4), value: track.id)

            controls
                .frame(maxWidth: .infinity)
                .staggered(appeared, index: 3, enabled: theme.staggerContent)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            transportButton("backward.fill", label: "Previous", size: 34, prominent: false) {
                previousTaps += 1
                store.previous()
            }
            .symbolEffect(.bounce.down, value: previousTaps)

            transportButton(store.isPlaying ? "pause.fill" : "play.fill",
                            label: store.isPlaying ? "Pause" : "Play", size: 40, prominent: true) {
                store.togglePlayPause()
            }

            transportButton("forward.fill", label: "Next", size: 34, prominent: false) {
                nextTaps += 1
                store.next()
            }
            .symbolEffect(.bounce.down, value: nextTaps)
        }
    }

    private func progress(duration: TimeInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = min(store.position(at: context.date), duration)
            let position = scrubFraction.map { $0 * duration } ?? live
            HStack(spacing: 8) {
                Text(Self.format(position))
                ScrubBar(
                    fraction: duration > 0 ? position / duration : 0,
                    accent: theme.accent,
                    isScrubbing: scrubFraction != nil,
                    onScrub: { scrubFraction = $0 },
                    onCommit: { fraction in
                        store.seek(to: fraction * duration)
                        scrubFraction = nil
                    }
                )
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Self.format(position)) of \(Self.format(duration))")
                .accessibilityAdjustableAction { direction in
                    let step: TimeInterval = direction == .increment ? 10 : -10
                    store.seek(to: live + step)
                }
                Text(Self.format(duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(theme.text.opacity(0.8))
        }
    }

    private func transportButton(
        _ symbol: String, label: String, size: CGFloat, prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? theme.onText : theme.text)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? theme.text : theme.text.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .animation(.smooth(duration: 0.25), value: store.isPlaying)
        .accessibilityLabel(label)
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Shrinks a little under the pointer with a springy release.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    /// Fades and lifts a section in, later sections after earlier ones.
    func staggered(_ appeared: Bool, index: Int, enabled: Bool) -> some View {
        opacity(appeared || !enabled ? 1 : 0)
            .offset(y: appeared || !enabled ? 0 : 10)
            .blur(radius: appeared || !enabled ? 0 : 3)
            .animation(
                enabled ? .spring(response: 0.42, dampingFraction: 0.8).delay(0.1 + Double(index) * 0.05) : nil,
                value: appeared
            )
    }
}
