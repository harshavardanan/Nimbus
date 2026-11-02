import SwiftUI

/// Album art on the left wing, live waveform on the right.
struct CompactView: View {
    @ObservedObject var store: NowPlayingStore
    let settings: IslandSettings
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack {
            if settings.showCompactArtwork {
                ArtworkView(image: store.artwork, accent: theme.accent, cornerRadius: 6)
                    .frame(width: 20, height: 20)
                    .shadow(color: theme.accent.opacity(0.55), radius: 5)
                    .id(store.track?.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if settings.showWaveform {
                WaveformView(isPlaying: store.isPlaying, color: theme.accent)
                    .frame(width: 24, height: 16)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.track?.id)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Cover art arrives a moment after the track, so fade it in.
        .animation(.easeOut(duration: 0.3), value: image != nil)
        .accessibilityHidden(true)
    }
}

/// Four bars that dance while playing and ease down to rest when paused.
struct WaveformView: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let speed = 2.6 + 0.7 * Double(i)
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: isPlaying ? 4 + 11 * abs(sin(t * speed + Double(i) * 1.3)) : 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.3), value: isPlaying)
        .accessibilityHidden(true)
    }
}
