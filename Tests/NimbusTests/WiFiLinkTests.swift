import Foundation
import Testing
@testable import Nimbus

private func line(_ text: String) -> HTTPRequestLine? { HTTPRequestLine.parse(Data(text.utf8)) }

@Suite("HTTP request line")
struct HTTPParsingTests {
    @Test func readsPathAndQuery() {
        let r = line("GET /b?token=abc&name=iPhone&level=82 HTTP/1.1\r\nHost: x\r\n\r\n")
        #expect(r?.method == "GET")
        #expect(r?.path == "/b")
        #expect(r?.query["level"] == "82")
        #expect(r?.query["name"] == "iPhone")
    }

    @Test func decodesPercentEscapesAndLowercasesKeys() {
        let r = line("GET /c?TOKEN=a&Title=Hi%20there HTTP/1.1\r\n\r\n")
        #expect(r?.query["title"] == "Hi there")
        #expect(r?.query["token"] == "a")
    }

    @Test func postIsAcceptedOtherMethodsAreNot() {
        #expect(line("POST /ping?token=a HTTP/1.1\r\n\r\n")?.method == "POST")
        #expect(line("DELETE /ping HTTP/1.1\r\n\r\n") == nil)
        #expect(line("PUT /ping HTTP/1.1\r\n\r\n") == nil)
    }

    @Test func garbageIsRejected() {
        #expect(line("") == nil)
        #expect(line("not http") == nil)
        #expect(HTTPRequestLine.parse(Data([0x00, 0xff, 0xfe])) == nil)
    }

    @Test func longValuesAreClipped() {
        let long = String(repeating: "a", count: 1000)
        #expect(line("GET /b?name=\(long) HTTP/1.1\r\n\r\n")?.query["name"]?.count == 200)
    }
}

@Suite("Routing and the token")
struct RoutingTests {
    private func request(_ path: String, _ query: [String: String]) -> HTTPRequestLine {
        HTTPRequestLine(method: "GET", path: path, query: query)
    }

    @Test func tokenIsRequired() {
        #expect(SyncCenter.route(request("/ping", [:]), token: "secret") == .unauthorized)
        #expect(SyncCenter.route(request("/ping", ["token": "wrong"]), token: "secret") == .unauthorized)
        #expect(SyncCenter.route(request("/ping", ["token": ""]), token: "secret") == .unauthorized)
        #expect(SyncCenter.route(request("/ping", ["token": "secret"]), token: "secret") == .ping)
    }

    @Test func tokenIsNotPassedOn() throws {
        guard case .battery(let data) = SyncCenter.route(request("/b", ["token": "secret", "level": "5"]), token: "secret") else {
            Issue.record("expected battery"); return
        }
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(fields == ["level": "5"])
    }

    @Test func routes() {
        func r(_ p: String) -> SyncCenter.HTTPRoute { SyncCenter.route(request(p, ["token": "t"]), token: "t") }
        if case .battery = r("/b") {} else { Issue.record("/b") }
        if case .timer = r("/t") {} else { Issue.record("/t") }
        if case .command = r("/c") {} else { Issue.record("/c") }
        #expect(r("/etc/passwd") == .notFound)
        #expect(r("/../../x") == .notFound)
        #expect(r("/") == .notFound)
    }

    @Test func wrongTokenBeatsEveryRoute() {
        for path in ["/b", "/t", "/c", "/ping", "/nothing"] {
            #expect(SyncCenter.route(request(path, ["token": "nope"]), token: "t") == .unauthorized)
        }
    }

    @Test func constantTimeCompare() {
        #expect(SyncCenter.constantTimeEqual("abc", "abc"))
        #expect(!SyncCenter.constantTimeEqual("abc", "abd"))
        #expect(!SyncCenter.constantTimeEqual("abc", "abcd"))
        #expect(!SyncCenter.constantTimeEqual("", "a"))
        #expect(SyncCenter.constantTimeEqual("", ""))
    }
}

@Suite("Shortcut builder")
struct ShortcutBuilderTests {
    private let base = "http://My-Mac.local:8765"

    @Test func variableOffsetsAreInUTF16Units() {
        // The emoji is two UTF-16 units, so the variable sits at offset 3, not 2.
        let s = ShortcutBuilder.tokenString([.text("a😀"), .variable(id: "ID", name: "N")])
        let value = s["Value"] as? [String: Any]
        let text = value?["string"] as? String
        let marks = value?["attachmentsByRange"] as? [String: Any]
        #expect(text == "a😀\u{FFFC}")
        #expect(marks?["{3, 1}"] != nil)
    }

    @Test func buildsTheFiveShortcuts() {
        let names = ShortcutBuilder.definitions(base: base, token: "tok").map(\.name)
        #expect(names == ["Nimbus Sync", "Nimbus Timer", "Nimbus Pomodoro", "Nimbus Pause", "Nimbus Skip"])
    }

    @Test func everyRequestCarriesTheAddressAndToken() {
        for item in ShortcutBuilder.definitions(base: base, token: "tok123") {
            let urls = item.actions.filter { ($0["WFWorkflowActionIdentifier"] as? String) == "is.workflow.actions.downloadurl" }
            #expect(urls.count == 1, "\(item.name) should make exactly one request")
            let params = urls.first?["WFWorkflowActionParameters"] as? [String: Any]
            let text = ((params?["WFURL"] as? [String: Any])?["Value"] as? [String: Any])?["string"] as? String
            #expect(text?.hasPrefix("\(base)/") == true)
            #expect(text?.contains("token=tok123") == true)
        }
    }

    @Test func variablesPointAtEarlierActions() {
        for item in ShortcutBuilder.definitions(base: base, token: "t") {
            var seen = Set<String>()
            for action in item.actions {
                let params = action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
                // Every variable used must come from an action that already ran.
                let url = ((params["WFURL"] as? [String: Any])?["Value"] as? [String: Any])?["attachmentsByRange"] as? [String: [String: Any]]
                for mark in (url ?? [:]).values {
                    #expect(seen.contains(mark["OutputUUID"] as? String ?? ""), "\(item.name) uses a variable before it exists")
                }
                if let id = params["UUID"] as? String { seen.insert(id) }
            }
        }
    }

    @Test func plistRoundTrips() throws {
        for item in ShortcutBuilder.definitions(base: base, token: "t") {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ShortcutBuilder.workflow(item.actions, color: item.color), format: .binary, options: 0)
            let back = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            #expect((back?["WFWorkflowActions"] as? [Any])?.count == item.actions.count)
        }
    }
}
