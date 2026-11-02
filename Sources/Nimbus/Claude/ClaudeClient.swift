import Foundation

struct ChatTurn: Equatable {
    enum Role: String { case user, assistant }
    var role: Role
    var text: String
}

struct ClaudeError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Minimal streaming client for the Anthropic Messages API.
enum ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Yields the answer in small pieces as it is generated.
    static func stream(apiKey: String, model: String, system: String, turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.timeoutInterval = 60
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 700,
                        "stream": true,
                        "system": system,
                        "messages": turns.map { ["role": $0.role.rawValue, "content": $0.text] },
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ClaudeError(message: "No response.") }
                    guard http.statusCode == 200 else {
                        var raw = ""
                        for try await line in bytes.lines { raw += line }
                        throw ClaudeError(message: errorMessage(status: http.statusCode, body: raw))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        switch event["type"] as? String {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any], let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            throw ClaudeError(message: message ?? "The API returned an error.")
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(status: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (json["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        switch status {
        case 401: return "The API key was rejected. Check it in Settings."
        case 429: return "Rate limited. Try again in a moment."
        default: return "The API returned status \(status)."
        }
    }
}
