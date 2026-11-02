import Foundation
import Testing
@testable import Nimbus

private func json(_ text: String) -> Data { Data(text.utf8) }

@Suite("Battery files from Shortcuts")
struct BatteryFileTests {
    @Test func numberAsText() {
        let d = BatteryReader.parseSync(json(#"{"name": "iPhone", "level": "82", "kind": "iphone"}"#), modified: nil, fallbackName: "x")
        #expect(d?.level == 82)
        #expect(d?.name == "iPhone")
        #expect(d?.kind == .iphone)
    }

    @Test func fractionBecomesPercent() {
        let d = BatteryReader.parseSync(json(#"{"Name": "iPad", "Battery": 0.47, "type": "ipad"}"#), modified: nil, fallbackName: "x")
        #expect(d?.level == 47)
        #expect(d?.kind == .ipad)
    }

    @Test func percentSignAndWatch() {
        let d = BatteryReader.parseSync(json(#"{"name": "Watch", "level": "15%", "kind": "watch"}"#), modified: nil, fallbackName: "x")
        #expect(d?.level == 15)
        #expect(d?.kind == .watch)
    }

    @Test func fallbackNameWhenMissing() {
        let d = BatteryReader.parseSync(json(#"{"level": 50}"#), modified: nil, fallbackName: "nimbus-phone")
        #expect(d?.name == "nimbus-phone")
    }

    @Test func rejectsBadFiles() {
        #expect(BatteryReader.parseSync(json("not json"), modified: nil, fallbackName: "x") == nil)
        #expect(BatteryReader.parseSync(json(#"{"name": "NoLevel"}"#), modified: nil, fallbackName: "x") == nil)
        #expect(BatteryReader.parseSync(json(#"{"level": 250}"#), modified: nil, fallbackName: "x") == nil)
        #expect(BatteryReader.parseSync(json(#"{"level": -5}"#), modified: nil, fallbackName: "x") == nil)
    }

    @Test func keepsModifiedDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(BatteryReader.parseSync(json(#"{"level": 10}"#), modified: date, fallbackName: "x")?.updated == date)
    }
}

@Suite("One file per device")
struct MultiDeviceTests {
    @Test func deviceModelPicksTheIcon() {
        let ipad = BatteryReader.parseSync(json(#"{"name": "Harsha's iPad", "level": 40, "kind": "iPad"}"#), modified: nil, fallbackName: "x")
        let phone = BatteryReader.parseSync(json(#"{"name": "Harsha's iPhone", "level": 80, "kind": "iPhone"}"#), modified: nil, fallbackName: "x")
        #expect(ipad?.kind == .ipad)
        #expect(phone?.kind == .iphone)
        #expect(ipad?.id != phone?.id) // two devices never collapse into one tile
    }

    @Test func fileNamesAreClassified() {
        #expect(SyncCenter.role(of: "nimbus-command.json") == .command)
        #expect(SyncCenter.role(of: "nimbus-timer-Harsha's iPhone.json") == .timer)
        #expect(SyncCenter.role(of: "nimbus-device-Harsha's iPad.json") == .other)
    }

    @Test func aDeviceNamedLikeACommandIsStillADevice() {
        #expect(SyncCenter.role(of: "nimbus-device-Command Center iPad.json") == .other)
        #expect(SyncCenter.role(of: "nimbus-device-Timer Phone.json") == .other)
        #expect(SyncCenter.role(of: "notes.json") == .other)
    }
}

@Suite("Accessory batteries (pmset)")
struct AccessoryTests {
    private let sample = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=34537571)\t75%; discharging; 6:36 remaining present: true
     -Keychron K3 Max (id=47651011)\t38%; 
     -MX Master 2S (id=47651012)\t50%; charging
    """

    @Test func readsAccessoriesAndSkipsTheMac() {
        let devices = BatteryReader.parseAccessories(sample)
        #expect(devices.map(\.name) == ["Keychron K3 Max", "MX Master 2S"])
        #expect(devices.map(\.level) == [38, 50])
    }

    @Test func chargingFlag() {
        let devices = BatteryReader.parseAccessories(sample)
        #expect(devices[0].isCharging == false)
        #expect(devices[1].isCharging == true)
    }

    @Test func iconsFromNames() {
        let devices = BatteryReader.parseAccessories(sample)
        #expect(devices[0].kind == .keyboard)
        #expect(devices[1].kind == .mouse)
    }

    @Test func emptyAndGarbage() {
        #expect(BatteryReader.parseAccessories("").isEmpty)
        #expect(BatteryReader.parseAccessories("nothing useful here").isEmpty)
    }
}

@Suite("Bluetooth profiler JSON")
struct BluetoothTests {
    @Test func readsMainAndEarbudLevels() {
        let data = json("""
        {"SPBluetoothDataType": [{"device_connected": [
          {"AirPods": {"device_address": "AA", "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "65%"}},
          {"Mouse": {"device_address": "BB", "device_batteryLevelMain": "90%", "device_minorType": "Mouse"}},
          {"Soundbar": {"device_address": "CC", "device_minorType": "Speaker"}}
        ]}]}
        """)
        let devices = BatteryReader.parseBluetooth(data)
        #expect(devices.count == 2) // the soundbar has no battery
        #expect(devices.first { $0.name == "AirPods" }?.level == 65) // the weaker bud
        #expect(devices.first { $0.name == "Mouse" }?.level == 90)
    }

    @Test func kindsIncludeDevicesWithoutBattery() {
        let data = json(#"{"SPBluetoothDataType": [{"device_connected": [{"Keychron K3 Max": {"device_minorType": "Keyboard"}}]}]}"#)
        #expect(BatteryReader.parseBluetoothKinds(data)["keychron k3 max"] == .keyboard)
    }

    @Test func percentHelper() {
        #expect(BatteryReader.percent("85%") == 85)
        #expect(BatteryReader.percent("abc") == nil)
        #expect(BatteryReader.percent("500%") == nil)
        #expect(BatteryReader.percent(nil) == nil)
    }
}

@Suite("Commands from other devices")
struct CommandTests {
    @Test func startWithStageAndMinutes() {
        let c = SyncCenter.parseCommand(json(#"{"action": "pomodoro.start", "stage": "focus", "minutes": 25}"#))
        #expect(c == .start(stage: .focus, minutes: 25))
    }

    @Test func stageNamesAreForgiving() {
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.start", "stage": "short_break"}"#)) == .start(stage: .shortBreak, minutes: nil))
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.start", "stage": "Long Break"}"#)) == .start(stage: .longBreak, minutes: nil))
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.start", "stage": "nonsense"}"#)) == .start(stage: nil, minutes: nil))
    }

    @Test func minutesAsText() {
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.start", "minutes": "20"}"#)) == .start(stage: nil, minutes: 20))
    }

    @Test func simpleActions() {
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.pause"}"#)) == .pause)
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.resume"}"#)) == .resume)
        #expect(SyncCenter.parseCommand(json(#"{"action": "pomodoro.reset"}"#)) == .reset)
        #expect(SyncCenter.parseCommand(json(#"{"ACTION": "Pomodoro.Skip"}"#)) == .skip)
    }

    @Test func notifyIsTrimmed() {
        let long = String(repeating: "a", count: 300)
        let c = SyncCenter.parseCommand(json(#"{"action": "notify", "title": "Hi", "line": "\#(long)"}"#))
        guard case .notify(let title, let line, _) = c else { Issue.record("not a notify"); return }
        #expect(title == "Hi")
        #expect(line.count == 120)
    }

    @Test func unknownAndBrokenAreIgnored() {
        #expect(SyncCenter.parseCommand(json(#"{"action": "rm -rf /"}"#)) == nil)
        #expect(SyncCenter.parseCommand(json(#"{"action": "open", "url": "http://evil"}"#)) == nil)
        #expect(SyncCenter.parseCommand(json("garbage")) == nil)
        #expect(SyncCenter.parseCommand(json("{}")) == nil)
    }
}

@Suite("Phone timers")
struct RemoteTimerTests {
    private let written = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func startsWhenFileWasWritten() {
        let t = SyncCenter.parseTimer(json(#"{"name": "iPhone", "label": "Tea", "minutes": 10}"#), modified: written, fileName: "a.json")
        #expect(t?.start == written)
        #expect(t?.end == written.addingTimeInterval(600))
        #expect(t?.label == "Tea")
        #expect(t?.device == "iPhone")
    }

    @Test func explicitStartOverrides() {
        let t = SyncCenter.parseTimer(json(#"{"minutes": 5, "start": 1700000100}"#), modified: written, fileName: "a.json")
        #expect(t?.start == Date(timeIntervalSince1970: 1_700_000_100))
        let iso = SyncCenter.parseTimer(json(#"{"minutes": 5, "start": "2023-11-14T22:15:00Z"}"#), modified: written, fileName: "a.json")
        #expect(iso?.start == ISO8601DateFormatter().date(from: "2023-11-14T22:15:00Z"))
    }

    @Test func defaultsAndLimits() {
        let t = SyncCenter.parseTimer(json(#"{"minutes": "3"}"#), modified: written, fileName: "a.json")
        #expect(t?.device == "iPhone")
        #expect(t?.label == "Timer")
        #expect(SyncCenter.parseTimer(json(#"{"minutes": 0}"#), modified: written, fileName: "a.json") == nil)
        #expect(SyncCenter.parseTimer(json(#"{"minutes": 99999}"#), modified: written, fileName: "a.json") == nil)
        #expect(SyncCenter.parseTimer(json("nope"), modified: written, fileName: "a.json") == nil)
    }

    @Test func remainingAndFraction() {
        let t = RemoteTimer(id: "x", device: "d", label: "l", start: written, end: written.addingTimeInterval(100))
        #expect(t.remaining(at: written.addingTimeInterval(40)) == 60)
        #expect(t.remaining(at: written.addingTimeInterval(500)) == 0)
        #expect(t.fraction(at: written.addingTimeInterval(50)) == 0.5)
        #expect(t.fraction(at: written.addingTimeInterval(-10)) == 0)
    }
}
