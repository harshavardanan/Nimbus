import Foundation
import Testing
@testable import Nimbus

@Suite("Island settings")
struct SettingsTests {
    @Test func clampingKeepsValuesInRange() {
        var s = IslandSettings()
        s.expandedWidth = 100_000
        s.expandedHeight = -50
        s.openDamping = 5
        s.compactWing = 0
        let c = s.clamped()
        #expect(c.expandedWidth == SettingsLimits.expandedWidth.upperBound)
        #expect(c.expandedHeight == SettingsLimits.expandedHeight.lowerBound)
        #expect(c.openDamping == SettingsLimits.damping.upperBound)
        #expect(c.compactWing == SettingsLimits.compactWing.lowerBound)
    }

    @Test func roundTripsThroughJSON() throws {
        var s = IslandSettings()
        s.transitionStyle = .pop
        s.backgroundStyle = .glass
        s.expandedWidth = 500
        let back = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func presetsChangeLookOnly() {
        var s = IslandSettings()
        s.expandedWidth = 480
        ThemePreset.paper.apply(to: &s)
        #expect(s.backgroundStyle == .solid)
        #expect(s.textColor.luminance < 0.5)
        #expect(s.expandedWidth == 480) // size untouched
    }

    @Test func colourLuminance() {
        #expect(RGBAColor(1, 1, 1).luminance > 0.99)
        #expect(RGBAColor(0, 0, 0).luminance == 0)
    }
}

@MainActor
@Suite("Pomodoro cycle")
struct PomodoroTests {
    @Test func skipWalksTheCycleWithoutCountingSessions() {
        let timer = TimerStore()
        timer.restartCycle()
        #expect(timer.stage == .focus)
        timer.skip()
        #expect(timer.stage == .shortBreak)
        timer.skip()
        #expect(timer.stage == .focus)
        #expect(timer.completedInCycle == 0)
    }

    @Test func settingMinutesOnlyWhileIdle() {
        let timer = TimerStore()
        timer.restartCycle()
        let before = timer.selectedMinutes
        timer.start()
        timer.setMinutes(before + 7)
        #expect(timer.selectedMinutes == before) // ignored while running
        timer.reset()
        timer.setMinutes(before + 7)
        #expect(timer.selectedMinutes == before + 7)
        timer.setMinutes(before) // put it back
    }

    @Test func remoteStartSetsStageAndLength() {
        let timer = TimerStore()
        timer.restartCycle()
        timer.remoteStart(stage: .shortBreak, minutes: 4)
        #expect(timer.stage == .shortBreak)
        #expect(timer.phase == .running)
        #expect(timer.selectedMinutes == 4)
        timer.reset()
    }

    @Test func lengthsAreClamped() {
        let timer = TimerStore()
        timer.restartCycle()
        let before = timer.selectedMinutes
        timer.setMinutes(10_000)
        #expect(timer.selectedMinutes == TimerStore.minutesRange.upperBound)
        timer.setMinutes(0)
        #expect(timer.selectedMinutes == TimerStore.minutesRange.lowerBound)
        timer.setMinutes(before)
    }
}
