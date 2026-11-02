import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState

    var body: some View {
        let size = state.shownSize
        let s = state.settings
        let theme = state.theme
        let shape = NotchShape(bottomRadius: state.bottomRadius)

        ZStack(alignment: .top) {
            IslandBackground(settings: s, accent: theme.accent, shape: shape)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    content(fadeDelay: s.contentFadeDelay)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .clipShape(shape)
                }
                .shadow(
                    color: .black.opacity(state.mode == .expanded && s.showShadow ? 0.35 : 0),
                    radius: 14, y: 6
                )
        }
        .scaleEffect(state.islandScale, anchor: .top)
        .opacity(state.islandOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandTheme, theme)
        .foregroundStyle(theme.text)
        // Corner radius, shadow and the content swap follow the mode's spring.
        .animation(state.animation, value: state.mode)
    }

    /// How content enters and leaves depends on the transition style.
    private func contentTransition(fadeDelay: Double) -> AnyTransition {
        let leave = AnyTransition.opacity.animation(.easeIn(duration: 0.1))
        switch state.settings.transitionStyle {
        case .classic:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                    .animation(.easeOut(duration: 0.24).delay(fadeDelay)),
                removal: leave)
        case .drop:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: -18))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(fadeDelay)),
                removal: leave)
        case .pop:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .top))
                    .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(fadeDelay)),
                removal: leave)
        case .elastic:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top))
                    .animation(.spring(response: 0.5, dampingFraction: 0.45).delay(fadeDelay)),
                removal: leave)
        case .dissolve:
            return .asymmetric(
                insertion: .modifier(active: BlurFade(radius: 14, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
                    .animation(.easeOut(duration: 0.3).delay(fadeDelay)),
                removal: .modifier(active: BlurFade(radius: 8, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
                    .animation(.easeIn(duration: 0.15)))
        }
    }

    @ViewBuilder
    private func content(fadeDelay: Double) -> some View {
        let transition = contentTransition(fadeDelay: fadeDelay)
        switch state.mode {
        case .idle:
            Color.clear
        case .compact:
            if let live = state.liveWidget {
                live.compactView(settings: state.settings)
                    .id(live.id)
                    .transition(transition)
            } else {
                Color.clear
            }
        case .expanded:
            WidgetContainer(state: state)
                .transition(transition)
        }
    }
}

/// The expanded island: the selected widget, widget icons spread on both sides of the notch,
/// and the settings gear at the far right.
struct WidgetContainer: View {
    @ObservedObject var state: IslandState
    @Environment(\.islandTheme) private var theme
    @State private var appeared = false
    @Namespace private var selectionNamespace

    var body: some View {
        let current = state.selectedWidget

        ZStack {
            if let widget = current {
                widget.expandedView(topInset: state.closedSize.height)
                    .id(widget.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
            } else {
                Text("No widgets enabled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.6))
            }
        }
        .animation(.smooth(duration: 0.32), value: current?.id)
        .overlay(alignment: .topLeading) { iconRow(Array(layout.left), selectedID: current?.id, width: layout.iconWidth) }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                iconRow(Array(layout.right), selectedID: current?.id, width: layout.iconWidth)
                gear(width: layout.iconWidth)
            }
        }
        .onAppear { appeared = true }
    }

    private var bandInset: CGFloat { max(0, (state.closedSize.height - 24) / 2) }

    /// Widgets are split evenly either side of the notch (the gear takes one slot on the right).
    /// The icons shrink a little when there are many, so all of them always fit.
    private var layout: (left: ArraySlice<any IslandWidget>, right: ArraySlice<any IslandWidget>, iconWidth: CGFloat) {
        let widgets = state.registry.enabled
        let leftCount = (widgets.count + 1) / 2
        let left = widgets.prefix(leftCount)
        let right = widgets.dropFirst(leftCount)
        let sideRoom = max(60, (state.targetSize.width - state.closedSize.width) / 2 - 20)
        let slots = CGFloat(max(left.count, right.count + 1))
        return (left, right, min(28, sideRoom / slots))
    }

    private func iconRow(_ widgets: [any IslandWidget], selectedID: String?, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(widgets, id: \.id) { widget in
                let selected = widget.id == selectedID
                Button { state.selectedID = widget.id } label: {
                    Image(systemName: widget.symbol)
                        .font(.system(size: width < 24 ? 10 : 11, weight: .semibold))
                        .foregroundStyle(theme.text.opacity(selected ? 1 : 0.55))
                        .frame(width: width, height: 24)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(theme.text.opacity(0.18))
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help(widget.title)
                .accessibilityLabel(widget.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: selectedID)
        .padding(.top, bandInset)
        .padding(.horizontal, 10)
        .staggered(appeared, index: 4, enabled: theme.staggerContent)
    }

    private func gear(width: CGFloat) -> some View {
        Button(action: state.openSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: width < 24 ? 10 : 12, weight: .semibold))
                .foregroundStyle(theme.text.opacity(0.7))
                .frame(width: width, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .padding(.top, bandInset)
        .padding(.trailing, 10)
        .help("Settings")
        .accessibilityLabel("Open settings")
        .staggered(appeared, index: 4, enabled: theme.staggerContent)
    }
}

private struct BlurFade: ViewModifier {
    var radius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}
