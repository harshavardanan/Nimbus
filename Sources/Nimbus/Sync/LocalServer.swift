import Foundation
import Network

/// The first line of an HTTP request, split into what Nimbus needs.
struct HTTPRequestLine: Equatable {
    var method: String
    var path: String
    var query: [String: String]

    /// Reads `GET /b?level=82&name=iPhone HTTP/1.1`. Only the request line matters; headers and
    /// bodies are ignored, because everything a Shortcut sends fits in the address.
    static func parse(_ data: Data) -> HTTPRequestLine? {
        guard let text = String(data: data.prefix(8192), encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first ?? text.components(separatedBy: "\n").first
        else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, ["GET", "POST"].contains(String(parts[0])),
              let components = URLComponents(string: "http://nimbus" + parts[1])
        else { return nil }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = String((item.value ?? "").prefix(200))
        }
        return HTTPRequestLine(method: String(parts[0]), path: components.path, query: query)
    }
}

/// A tiny HTTP listener on the local network. It answers requests from your own devices and
/// nothing else: every request needs the private token, and only fixed routes exist.
final class LocalServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequestLine) async -> (status: Int, body: String)

    private let queue = DispatchQueue(label: "nimbus.server")
    private var listener: NWListener?
    var handler: Handler = { _ in (503, "unavailable") }
    var onState: @Sendable (String) -> Void = { _ in }

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: .tcp, on: nwPort) else {
            onState("Couldn't use port \(port)")
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState("Listening on port \(port)")
            case .failed(let error): self?.onState("Stopped: \(error.localizedDescription)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let handler = self.handler
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            guard error == nil, let data, let request = HTTPRequestLine.parse(data) else {
                Self.send(connection, 400, "bad request")
                return
            }
            Task {
                let reply = await handler(request)
                Self.send(connection, reply.status, reply.body)
            }
        }
        // A connection that never finishes sending is dropped.
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }

    private static func send(_ connection: NWConnection, _ status: Int, _ body: String) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 429: "Too Many Requests"][status] ?? "Error"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
