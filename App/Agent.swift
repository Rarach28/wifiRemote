// The login agent (WiFiRemote --agent, from Contents/Library/LaunchAgents): helper/remote.py behind a tiny HTTP
// server on 127.0.0.1 that wants BuildConfig.agentToken. The window and the sandboxed widgets both use it.
import Foundation
import Network

enum Agent {
    static let plist = "io.github.rarach28.wifiremote.agent.plist"
    nonisolated(unsafe) static var helper = Helper()
    /// The TV the helper is talking to; follows Store.activeHost, which the window changes.
    nonisolated(unsafe) static var helperHost = Store.activeHost

    static func run() -> Never {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                 port: NWEndpoint.Port(rawValue: BuildConfig.agentPort)!)
        guard let listener = try? NWListener(using: params) else { exit(1) }
        listener.newConnectionHandler = { handle($0) }
        listener.stateUpdateHandler = { if case .failed = $0 { exit(1) } }   // launchd starts us again
        listener.start(queue: .main)
        dispatchMain()
    }

    private static func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return connection.cancel() }
            let lines = text.components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ") ?? []
            let token = lines.first { $0.lowercased().hasPrefix("x-token:") }
                .map { $0.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            guard request.count >= 2, request[0] == "GET", token == BuildConfig.agentToken else {
                return reply(connection, 403, ["error": "forbidden"])
            }
            let parts = (URLComponents(string: String(request[1]))?.path ?? "").split(separator: "/").map(String.init)

            if parts == ["buttons"] {
                let tv = Store.activeTv
                return reply(connection, 200, [
                    "tv": tv?.name ?? "",
                    "apps": Store.buttons(for: Store.activeHost).map { [$0.package, $0.name] },
                ])
            }
            let command: String
            switch parts.count {
            case 1 where ["state", "info", "installed"].contains(parts[0]): command = parts[0]
            case 2 where ["key", "app"].contains(parts[0]): command = parts[0] + " " + parts[1]
            default: return reply(connection, 404, ["error": "not found"])
            }
            // Switch the helper first if the window picked another TV since the last command.
            let host = Store.activeHost
            if host.isEmpty { return reply(connection, 502, ["error": "no tv"]) }
            if host != helperHost {
                helperHost = host
                helper.send("host " + host)
            }
            helper.send(command) { result in
                guard let result, (result as? [String: Any])?["error"] == nil else {
                    return reply(connection, 502, result ?? ["error": "tv unreachable"])
                }
                reply(connection, 200, result)
            }
        }
    }

    private static func reply(_ connection: NWConnection, _ code: Int, _ body: Any) {
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + json, completion: .contentProcessed { _ in connection.cancel() })
    }
}
