import Foundation
import Network

/// Tiny localhost HTTP server used for the OAuth redirect callback.
final class LoopbackHTTPServer: @unchecked Sendable {
    private var listener: NWListener?

    func start() throws -> URL {
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        let portBox = PortBox()
        let started = DispatchSemaphore(value: 0)
        var startError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port {
                    portBox.port = port.rawValue
                }
                started.signal()
            case .failed(let error):
                startError = error
                started.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { _ in }

        listener.start(queue: .global(qos: .userInitiated))
        _ = started.wait(timeout: .now() + 5)

        if let startError { throw startError }
        guard let port = portBox.port else {
            throw URLError(.cannotConnectToHost)
        }

        return URL(string: "http://localhost:\(port)/oauth2redirect")!
    }

    func waitForCode(timeout: TimeInterval = 300) async throws -> String {
        guard let listener else {
            throw URLError(.badServerResponse)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            let resumeOnce: (Result<String, Error>) -> Void = { result in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                listener.cancel()
                resumeOnce(.failure(URLError(.timedOut)))
            }
            timer.resume()

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    defer {
                        timer.cancel()
                        listener.cancel()
                    }

                    if let error {
                        resumeOnce(.failure(error))
                        return
                    }

                    guard let data,
                          let request = String(data: data, encoding: .utf8) else {
                        Self.respond(connection, status: 400, body: "Bad request")
                        resumeOnce(.failure(URLError(.badServerResponse)))
                        return
                    }

                    if let errorParam = Self.extractQueryItem("error", from: request) {
                        Self.respond(connection, status: 400, body: "Google login error: \(errorParam)")
                        resumeOnce(.failure(NSError(
                            domain: "OAuth",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: errorParam]
                        )))
                        return
                    }

                    guard let code = Self.extractQueryItem("code", from: request) else {
                        Self.respond(connection, status: 400, body: "Missing code")
                        resumeOnce(.failure(URLError(.badServerResponse)))
                        return
                    }

                    Self.respond(
                        connection,
                        status: 200,
                        body: "Signed in to Access Log. You can close this tab and return to the app."
                    )
                    resumeOnce(.success(code))
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func extractQueryItem(_ name: String, from request: String) -> String? {
        let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? request
        guard let pathPart = firstLine.split(separator: " ").dropFirst().first else { return nil }
        guard let qIndex = pathPart.firstIndex(of: "?") else { return nil }
        let query = String(pathPart[pathPart.index(after: qIndex)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == name else { continue }
            return parts[1].removingPercentEncoding ?? parts[1]
        }
        return nil
    }

    private static func respond(_ connection: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : "Bad Request"
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;">
        <h2>\(body)</h2>
        </body></html>
        """
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class PortBox: @unchecked Sendable {
    var port: UInt16?
}
