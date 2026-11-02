import Foundation

/// Builds the iPhone Shortcuts that talk to Nimbus over Wi-Fi. Each one makes a plain web request
/// to this Mac, with the address and private token already filled in, then signs it so iOS accepts it.
enum ShortcutBuilder {
    enum Part {
        case text(String)
        case variable(id: String, name: String)
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Text that can contain variables, in the format Shortcuts stores them.
    static func tokenString(_ parts: [Part]) -> [String: Any] {
        var text = ""
        var attachments: [String: Any] = [:]
        for part in parts {
            switch part {
            case .text(let s):
                text += s
            case .variable(let id, let name):
                let offset = (text as NSString).length // positions are counted in UTF-16 units
                attachments["{\(offset), 1}"] = ["OutputUUID": id, "OutputName": name, "Type": "ActionOutput"]
                text += "\u{FFFC}"
            }
        }
        return [
            "Value": ["string": text, "attachmentsByRange": attachments],
            "WFSerializationType": "WFTextTokenString",
        ]
    }

    static func action(_ name: String, _ params: [String: Any]) -> [String: Any] {
        ["WFWorkflowActionIdentifier": "is.workflow.actions.\(name)", "WFWorkflowActionParameters": params]
    }

    static func workflow(_ actions: [[String: Any]], color: Int) -> [String: Any] {
        [
            "WFWorkflowClientVersion": "2900.0.1",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": color, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [] as [Any],
            "WFWorkflowInputContentItemClasses": [] as [Any],
            "WFWorkflowTypes": [] as [Any],
            "WFWorkflowActions": actions,
        ]
    }

    private static func newID() -> String { UUID().uuidString }

    /// "Get Contents of URL": a GET request to this Mac.
    private static func request(_ parts: [Part]) -> [String: Any] {
        action("downloadurl", ["UUID": newID(), "ShowHeaders": false, "WFURL": tokenString(parts)])
    }

    private static func ask(_ prompt: String, id: String) -> [String: Any] {
        action("ask", [
            "UUID": id, "WFAskActionPrompt": prompt, "WFInputType": "Number",
            "WFAskActionDefaultAnswer": "25", "WFAskActionDefaultAnswerNumber": "25",
        ])
    }

    /// All the shortcuts, by name. `base` looks like `http://My-Mac.local:8765`.
    static func definitions(base: String, token: String) -> [(name: String, color: Int, actions: [[String: Any]])] {
        let url = "\(base)/"
        let auth = "?token=\(token)"

        // Battery: this device's level, named by its model (iPhone, iPad).
        let level = newID(), model = newID()
        let battery: [[String: Any]] = [
            action("getbatterylevel", ["UUID": level]),
            action("getdevicedetails", ["UUID": model, "WFDeviceDetail": "Device Model"]),
            request([
                .text("\(url)b\(auth)&name="), .variable(id: model, name: "Device Details"),
                .text("&kind="), .variable(id: model, name: "Device Details"),
                .text("&level="), .variable(id: level, name: "Battery Level"),
            ]),
        ]

        // Timer: starts a Clock timer on the phone and shows the countdown on the Mac.
        let minutes = newID(), model2 = newID()
        let timer: [[String: Any]] = [
            ask("Timer length in minutes?", id: minutes),
            action("timer.start", ["WFDuration": [
                "Value": ["Unit": "min", "Magnitude": tokenString([.variable(id: minutes, name: "Provided Input")])],
                "WFSerializationType": "WFQuantityFieldValue",
            ]]),
            action("getdevicedetails", ["UUID": model2, "WFDeviceDetail": "Device Model"]),
            request([
                .text("\(url)t\(auth)&label=Timer&name="), .variable(id: model2, name: "Device Details"),
                .text("&minutes="), .variable(id: minutes, name: "Provided Input"),
            ]),
        ]

        // Pomodoro: starts a focus session on the Mac.
        let focus = newID()
        let pomodoro: [[String: Any]] = [
            ask("How many minutes of focus?", id: focus),
            request([
                .text("\(url)c\(auth)&action=pomodoro.start&stage=focus&minutes="),
                .variable(id: focus, name: "Provided Input"),
            ]),
        ]

        return [
            ("Nimbus Sync", 4282601983, battery),
            ("Nimbus Timer", 4271458815, timer),
            ("Nimbus Pomodoro", 4251333119, pomodoro),
            ("Nimbus Pause", 4292093695, [request([.text("\(url)c\(auth)&action=pomodoro.pause")])]),
            ("Nimbus Skip", 4292093695, [request([.text("\(url)c\(auth)&action=pomodoro.skip")])]),
        ]
    }

    /// Writes and signs every shortcut into `folder`, returning the files by name.
    static func build(base: String, token: String, into folder: URL) throws -> [String: URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        for item in definitions(base: base, token: token) {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: workflow(item.actions, color: item.color), format: .binary, options: 0
            )
            let unsigned = folder.appendingPathComponent("\(item.name) (unsigned).shortcut")
            let signed = folder.appendingPathComponent("\(item.name).shortcut")
            try plist.write(to: unsigned)
            try sign(unsigned, to: signed)
            try? FileManager.default.removeItem(at: unsigned) // the token is inside; don't leave a copy
            files[item.name] = signed
        }
        return files
    }

    /// iOS only imports signed shortcuts; `shortcuts sign` ships with macOS 12 and later.
    private static func sign(_ input: URL, to output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["sign", "--mode", "anyone", "--input", input.path, "--output", output.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure(message: "Couldn't sign the shortcut. \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
