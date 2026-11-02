import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var state: IslandState

    private enum Preview: String, CaseIterable, Identifiable {
        case live = "Live", idle = "Idle", compact = "Compact", expanded = "Expanded"
        var id: String { rawValue }
        var mode: IslandMode? {
            switch self {
            case .live: return nil
            case .idle: return .idle
            case .compact: return .compact
            case .expanded: return .expanded
            }
        }
    }

    @State private var preview = Preview.live
    @State private var message: String?
    @State private var isReplaying = false

    var body: some View {
        VStack(spacing: 0) {
            previewBar
            Divider()
            TabView {
                widgetsTab.tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
                lookTab.tabItem { Label("Look", systemImage: "paintpalette") }
                sizeTab.tabItem { Label("Size", systemImage: "arrow.up.left.and.arrow.down.right") }
                motionTab.tabItem { Label("Motion", systemImage: "wand.and.stars") }
                filesTab.tabItem { Label("Presets", systemImage: "square.and.arrow.down") }
            }
            .padding(.top, 4)
        }
        .frame(minWidth: 540, minHeight: 640)
    }

    // MARK: Preview

    private var previewBar: some View {
        HStack {
            Text("Preview on the notch").font(.headline)
            Spacer()
            Picker("Preview", selection: $preview) {
                ForEach(Preview.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .onChange(of: preview) { _, new in state.previewMode = new.mode }
        }
        .padding(12)
    }

    // MARK: Widgets

    private var widgetsTab: some View {
        Form {
            GeneralSettingsSection()
            Section("Show in the island") {
                ForEach(state.registry.widgets, id: \.id) { widget in
                    Toggle(isOn: Binding(
                        get: { state.registry.isEnabled(widget.id) },
                        set: { state.registry.setEnabled(widget.id, $0) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(widget.title)
                                Text(widget.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: widget.symbol).frame(width: 20)
                        }
                    }
                }
            }
            if let timer = state.registry.widget(id: "timer") as? TimerWidget {
                PomodoroSettingsSection(store: timer.store)
            }
            if let devices = state.registry.widget(id: "devices") as? DevicesWidget {
                DevicesSettingsSection(store: devices.store)
            }
            if let weather = state.registry.widget(id: "weather") as? WeatherWidget {
                WeatherSettingsSection(store: weather.store)
            }
            if let toggles = state.registry.widget(id: "toggles") as? QuickTogglesWidget {
                TogglesSettingsSection(store: toggles.store)
            }
            WiFiSettingsSection(sync: .shared)
            if let timer = state.registry.widget(id: "timer") as? TimerWidget {
                SyncSettingsSection(sync: .shared, timer: timer.store)
            }
            if let claude = state.registry.widget(id: "claude") as? ClaudeWidget {
                ClaudeSettingsSection(store: claude.store)
            }
            Section {
                Text("With more than one widget on, a switcher appears beside the notch when the island is open. The island opens on whatever is live, like a running timer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Look

    private var lookTab: some View {
        Form {
            Section("Theme") {
                HStack(spacing: 8) {
                    ForEach(ThemePreset.allCases) { preset in
                        Button {
                            store.apply(preset)
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.rawValue).fontWeight(store.settings.presetName == preset.rawValue ? .bold : .regular)
                                Text(preset.blurb).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.settings.presetName == preset.rawValue ? .accentColor : nil)
                    }
                }
            }

            Section("Background") {
                Picker("Style", selection: $store.settings.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                ColorPicker("Colour", selection: color(\.background), supportsOpacity: true)
                if store.settings.backgroundStyle == .gradient {
                    ColorPicker("Second colour", selection: color(\.backgroundSecondary), supportsOpacity: true)
                    slider("Angle", \.gradientAngle, SettingsLimits.gradientAngle, unit: "°")
                }
                slider("Opacity", \.backgroundOpacity, SettingsLimits.opacity, step: 0.01, format: "%.0f", scale: 100, unit: "%")
            }

            Section("Text and accent") {
                ColorPicker("Text colour", selection: color(\.textColor))
                Picker("Accent", selection: $store.settings.accentSource) {
                    ForEach(AccentSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.settings.accentSource == .fixed {
                    ColorPicker("Accent colour", selection: color(\.accent))
                }
            }

            Section("Edge") {
                Toggle("Drop shadow when expanded", isOn: $store.settings.showShadow)
                slider("Border width", \.borderWidth, SettingsLimits.border, step: 0.5, format: "%.1f")
                if store.settings.borderWidth > 0 {
                    ColorPicker("Border colour", selection: color(\.border), supportsOpacity: true)
                }
            }

            Section("Compact view") {
                Toggle("Show album art", isOn: $store.settings.showCompactArtwork)
                Toggle("Show waveform", isOn: $store.settings.showWaveform)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Size

    private var sizeTab: some View {
        Form {
            Section("Closed notch") {
                slider("Width adjust", \.notchWidthAdjust, SettingsLimits.notchWidthAdjust)
                slider("Height adjust", \.notchHeightAdjust, SettingsLimits.notchHeightAdjust)
                Text("The closed island matches your hardware notch. Anything smaller is hidden behind it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Compact") {
                slider("Wing width", \.compactWing, SettingsLimits.compactWing)
            }
            Section("Expanded") {
                slider("Width", \.expandedWidth, SettingsLimits.expandedWidth)
                slider("Height", \.expandedHeight, SettingsLimits.expandedHeight)
            }
            Section("Corner radius") {
                slider("Closed", \.idleRadius, SettingsLimits.radius)
                slider("Compact", \.compactRadius, SettingsLimits.radius)
                slider("Expanded", \.expandedRadius, SettingsLimits.radius)
            }
            Section("Position") {
                slider("Horizontal offset", \.offsetX, SettingsLimits.offsetX)
                slider("Drop below top edge", \.offsetY, SettingsLimits.offsetY)
                Picker("Display", selection: $store.settings.display) {
                    Text("Automatic (notched display)").tag("auto")
                    Text("Main display").tag("main")
                    ForEach(NSScreen.screens, id: \.localizedName) { Text($0.localizedName).tag($0.localizedName) }
                }
            }
            Section {
                Button("Reset size and position") { store.resetSize() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Motion

    private var motionTab: some View {
        Form {
            Section("Style") {
                HStack {
                    ForEach(MotionStyle.allCases) { style in
                        Button(style.rawValue) {
                            var s = store.settings
                            style.apply(to: &s)
                            store.settings = s
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Try them with the Live preview and hover the notch. Reduce Motion in System Settings always wins.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Open and close animation") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(TransitionStyle.allCases) { style in
                        let selected = store.settings.transitionStyle == style
                        Button {
                            store.settings.transitionStyle = style
                        } label: {
                            VStack(spacing: 2) {
                                Text(style.title).fontWeight(selected ? .bold : .regular)
                                Text(style.blurb).font(.caption2).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? .accentColor : nil)
                    }
                }
                HStack {
                    Button(isReplaying ? "Playing…" : "Replay") {
                        isReplaying = true
                        preview = .idle
                        state.replayTransition {
                            state.previewMode = nil
                            preview = .live
                            isReplaying = false
                        }
                    }
                    .disabled(isReplaying)
                    Text("Closes, opens, then closes the island on the notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Opening spring") {
                slider("Response", \.openResponse, SettingsLimits.response, step: 0.01, format: "%.2f", unit: " s")
                slider("Damping", \.openDamping, SettingsLimits.damping, step: 0.01, format: "%.2f")
            }
            Section("Closing spring") {
                slider("Response", \.closeResponse, SettingsLimits.response, step: 0.01, format: "%.2f", unit: " s")
                slider("Damping", \.closeDamping, SettingsLimits.damping, step: 0.01, format: "%.2f")
            }
            Section("Choreography") {
                if store.settings.transitionStyle == .classic {
                    Toggle("Width first, then height", isOn: $store.settings.staggerSize)
                }
                if store.settings.transitionStyle == .drop || (store.settings.transitionStyle == .classic && store.settings.staggerSize) {
                    slider("Stagger delay", \.staggerDelay, SettingsLimits.staggerDelay, step: 0.01, format: "%.2f", unit: " s")
                }
                Toggle("Reveal content piece by piece", isOn: $store.settings.staggerContent)
                slider("Content fade delay", \.contentFadeDelay, SettingsLimits.fadeDelay, step: 0.01, format: "%.2f", unit: " s")
            }
            Section("Hover") {
                slider("Open delay", \.openDelay, SettingsLimits.openDelay, step: 0.05, format: "%.2f", unit: " s")
                slider("Collapse delay", \.collapseDelay, SettingsLimits.collapseDelay, step: 0.05, format: "%.2f", unit: " s")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Presets and files

    private var filesTab: some View {
        Form {
            Section("Share your look") {
                HStack {
                    Button("Export…", action: exportSettings)
                    Button("Import…", action: importSettings)
                }
                Text("Exports every setting on this page as a JSON file you can share or keep as a backup.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Button("Reset everything to defaults", role: .destructive) { store.resetAll() }
            }
        }
        .formStyle(.grouped)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(store.settings.presetName)-nimbus.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Saved to \(url.lastPathComponent)"
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSettings(from: url)
            message = "Loaded \(url.lastPathComponent)"
        } catch {
            message = "That file isn't a Nimbus settings file."
        }
    }

    // MARK: Helpers

    private func color(_ keyPath: WritableKeyPath<IslandSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { store.settings[keyPath: keyPath].color },
            set: { store.settings[keyPath: keyPath] = RGBAColor(color: $0) }
        )
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<IslandSettings, Double>,
        _ range: ClosedRange<Double>,
        step: Double = 1,
        format: String = "%.0f",
        scale: Double = 1,
        unit: String = " pt"
    ) -> some View {
        let binding = Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0 }
        )
        return HStack {
            Text(title)
            Slider(value: binding, in: range, step: step)
            Text(String(format: format, binding.wrappedValue * scale) + unit)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}
