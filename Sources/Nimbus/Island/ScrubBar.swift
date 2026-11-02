import SwiftUI

/// Progress bar you can click or drag. `onScrub` fires continuously with the
/// pointer's position (0...1); `onCommit` fires once on release.
struct ScrubBar: View {
    let fraction: Double
    let accent: Color
    let isScrubbing: Bool
    var onScrub: (Double) -> Void
    var onCommit: (Double) -> Void

    @Environment(\.islandTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let filled = width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.22))
                Capsule()
                    .fill(accent)
                    .frame(width: filled)
                    .shadow(color: accent.opacity(isScrubbing ? 0.8 : 0), radius: 5)
                Circle()
                    .fill(theme.text)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .scaleEffect(isScrubbing ? 1 : 0.2)
                    .opacity(isScrubbing ? 1 : 0)
                    .offset(x: filled - 5.5)
            }
            .frame(height: isScrubbing ? 6 : 3)
            .frame(maxHeight: .infinity) // centred inside the taller hit area
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(Self.clamp($0.location.x / width)) }
                    .onEnded { onCommit(Self.clamp($0.location.x / width)) }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isScrubbing)
        }
        .frame(height: 16)
    }

    private static func clamp(_ f: Double) -> Double { min(max(f, 0), 1) }
}
