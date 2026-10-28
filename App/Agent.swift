// The login agent (WiFiRemote --agent, from Contents/Library/LaunchAgents): adb behind a tiny HTTP server on
// 127.0.0.1 that wants the install's token (SharedConfig). The window and the sandboxed widgets both use it.
import Foundation
import Network

enum Agent {
    static let plist = "io.github.rarach28.wifiremote.agent.plist"
    /// adb calls block, so they run here one at a time; HTTP is served on the main queue.
    private static let work = DispatchQueue(label: "agent.adb")

    static func run() -> Never {
        _ = SharedConfig.token
        let listener = listen(on: SharedConfig.port) ?? listen(on: 0)
        guard let listener else { exit(1) }
        listener.newConnectionHandler = { handle($0) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Port 0 means the system picked one: tell the app and the widgets.
                if let port = listener.port?.rawValue { SharedConfig.port = port }
            case .failed:
                // The port is taken. By our own agent (started twice): leave everything as it is. By anything
                // else: the next start (launchd restarts us) tries another port.
                if !agentAnswers(on: SharedConfig.port) { SharedConfig.port = UInt16.random(in: 49_152...65_000) }
                exit(1)
            default: break
            }
        }
        listener.start(queue: .main)
        work.async { _ = try? Adb.shared.binary() }   // fetch Platform-Tools early if this Mac has no adb
        dispatchMain()
    }

    /// Whether a WiFi Remote agent with this install's token already answers on the port.
    private static func agentAnswers(on port: UInt16) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/buttons") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue(SharedConfig.token, forHTTPHeaderField: "X-Token")
        let done = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return ok
    }

    private static func listen(on port: UInt16) -> NWListener? {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        return try? NWListener(using: params)
    }

    private static func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return connection.cancel() }
            let lines = text.components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ") ?? []
            let token = lines.first { $0.lowercased().hasPrefix("x-token:") }
                .map { $0.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            guard request.count >= 2, request[0] == "GET", token == SharedConfig.token else {
                return reply(connection, 403, ["error": "forbidden"])
            }
            let url = URLComponents(string: String(request[1]))
            let parts = (url?.path ?? "").split(separator: "/").map(String.init)
            let query = Dictionary((url?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                                   uniquingKeysWith: { first, _ in first })
            // The widgets' buttons need no adb: answer at once, even while adb is busy or downloading.
            if parts == ["buttons"] {
                let (code, body) = route(parts, query)
                return reply(connection, code, body)
            }
            work.async {
                let (code, body) = route(parts, query)
                DispatchQueue.main.async { reply(connection, code, body) }
            }
        }
    }

    private static func route(_ parts: [String], _ query: [String: String]) -> (Int, Any) {
        switch (parts.first ?? "", parts.count) {
        case ("buttons", 1):
            return (200, ["tv": Store.activeTv?.name ?? "",
                          "apps": Store.buttons(for: Store.activeHost).map { [$0.package, $0.name] }])
        case ("adb", 1):
            return (200, ["ready": (try? Adb.shared.binary()) != nil])
        case ("discover", 1):
            return (200, discover())
        case ("pair", 1):
            return pair(query["host"] ?? "", code: query["code"] ?? "")
        case ("connect", 1):
            return connect(host: query["host"] ?? "")
        case ("state", 1):
            return tvShell("dumpsys power | grep mWakefulness=") { ["awake": $0.contains("Awake")] }
        case ("info", 1):
            return tvShell("getprop ro.product.manufacturer; getprop ro.product.model") { out in
                let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                return ["manufacturer": lines.first ?? "", "model": lines.count > 1 ? lines[1] : ""]
            }
        case ("installed", 1):
            return tvShell("cmd package query-activities --brief -a android.intent.action.MAIN "
                           + "-c android.intent.category.LEANBACK_LAUNCHER") { out in
                var packages: [String] = []
                for line in out.split(separator: "\n") where line.contains("/") {
                    let pkg = String(line.trimmingCharacters(in: .whitespaces).split(separator: "/")[0])
                    if TvCommands.isPackage(pkg), !packages.contains(pkg) { packages.append(pkg) }
                }
                return packages.map { [$0, TvCommands.name(for: $0)] }
                    .sorted { $0[1].localizedCaseInsensitiveCompare($1[1]) == .orderedAscending }
            }
        case ("key", 2):
            guard let code = TvCommands.keys[parts[1]] else { return (400, ["error": "unknown key"]) }
            return tvShell("input keyevent \(code)") { _ in ["ok": true] }
        case ("app", 2):
            guard TvCommands.isPackage(parts[1]) else { return (400, ["error": "bad package"]) }
            // Wake first, so an app button also turns the TV on. Apps without a TV entry use the phone one.
            let pkg = parts[1]
            return tvShell("input keyevent KEYCODE_WAKEUP; "
                           + "monkey -p \(pkg) -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1 || "
                           + "monkey -p \(pkg) -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1") { _ in ["ok": true] }
        default:
            return (404, ["error": "not found"])
        }
    }

    // MARK: TV connection

    /// Connects the active TV if needed, runs one shell command and shapes its output.
    private static func tvShell(_ command: String, _ shape: (String) -> Any) -> (Int, Any) {
        guard var tv = Store.activeTv else { return (502, ["error": "no tv"]) }
        if let error = ensureConnected(&tv) { return (502, ["error": error]) }
        let (status, out) = Adb.shared.run(["-s", tv.serial, "shell", command])
        guard status == 0 else { return (502, ["error": "unreachable"]) }
        return (200, shape(out))
    }

    /// nil when the TV is ready; otherwise "unauthorized" (waiting for "Allow debugging?"), "unreachable" or
    /// "no adb" (Platform-Tools could not be found or downloaded).
    private static func ensureConnected(_ tv: inout SavedTv) -> String? {
        guard (try? Adb.shared.binary()) != nil else { return "no adb" }
        if Adb.shared.state(of: tv.serial) == "device" { return nil }
        _ = Adb.shared.run(["connect", tv.serial], timeout: 10)
        switch Adb.shared.state(of: tv.serial) {
        case "device": return nil
        case "unauthorized": return "unauthorized"
        default: break
        }
        // Wireless debugging moves to a new port when it is turned on again or the TV restarts: look it up.
        if tv.tls, let service = Adb.shared.services().first(where: {
            $0.host == tv.host && $0.type == "_adb-tls-connect._tcp" && $0.port != tv.port
        }) {
            _ = Adb.shared.run(["disconnect", tv.serial], timeout: 5)
            tv.port = service.port
            Store.update(tv)
            _ = Adb.shared.run(["connect", tv.serial], timeout: 10)
            if Adb.shared.state(of: tv.serial) == "device" { return nil }
        }
        return Adb.shared.state(of: tv.serial) == "unauthorized" ? "unauthorized" : "unreachable"
    }

    /// Connects a TV the window is adding: "host" for classic network debugging (port 5555), "host:port" for a
    /// wireless-debugging TV that is already paired.
    private static func connect(host raw: String) -> (Int, Any) {
        guard TvCommands.isHost(raw) else { return (400, ["error": "bad host"]) }
        let parts = raw.split(separator: ":")
        let host = String(parts[0])
        var tv = Store.tvs.first { $0.host == host } ?? SavedTv(host: host, name: host)
        if parts.count == 2, let port = Int(parts[1]) {
            tv.port = port
            tv.tls = port != 5555
        }
        Store.update(tv)
        if let error = ensureConnected(&tv) { return (502, ["error": error]) }
        return (200, ["ok": true, "port": tv.port, "tls": tv.tls])
    }

    /// Pairs with a TV showing "Pair device with pairing code" (Android 11+ wireless debugging), then connects
    /// to its debugging port, which it announces over mDNS once paired.
    private static func pair(_ raw: String, code: String) -> (Int, Any) {
        guard TvCommands.isHost(raw), code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            return (400, ["error": "bad input"])
        }
        guard (try? Adb.shared.binary()) != nil else { return (502, ["error": "no adb"]) }
        var pairing = raw
        if !raw.contains(":") {
            // Only the IP was given: take the pairing port the TV is announcing.
            guard let service = Adb.shared.services().first(where: {
                $0.host == raw && $0.type == "_adb-tls-pairing._tcp"
            }) else { return (502, ["error": "no pairing service"]) }
            pairing = "\(raw):\(service.port)"
        }
        let (_, out) = Adb.shared.run(["pair", pairing, code], timeout: 30)
        guard out.contains("Successfully paired") else { return (502, ["error": "pairing failed"]) }
        let host = String(pairing.split(separator: ":")[0])
        for _ in 0..<10 {
            if let service = Adb.shared.services().first(where: {
                $0.host == host && $0.type == "_adb-tls-connect._tcp"
            }) {
                return connect(host: "\(host):\(service.port)")
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return (502, ["error": "no debugging port"])
    }

    /// TVs announcing adb over mDNS: "pairing" (showing a pairing code), "paired" (wireless debugging, already
    /// paired with this Mac) or "classic" (network debugging on port 5555).
    private static func discover() -> [[String: Any]] {
        let rank = ["pairing": 3, "paired": 2, "classic": 1]
        var found: [String: [String: Any]] = [:]
        guard (try? Adb.shared.binary()) != nil else { return [] }
        for service in Adb.shared.services() {
            let kind: String
            switch service.type {
            case "_adb-tls-pairing._tcp": kind = "pairing"
            case "_adb-tls-connect._tcp": kind = "paired"
            default: kind = "classic"
            }
            if let existing = found[service.host]?["kind"] as? String, rank[existing]! >= rank[kind]! { continue }
            found[service.host] = ["host": service.host, "port": service.port, "kind": kind]
        }
        return found.values.sorted { ($0["host"] as? String ?? "") < ($1["host"] as? String ?? "") }
    }

    private static func reply(_ connection: NWConnection, _ code: Int, _ body: Any) {
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + json, completion: .contentProcessed { _ in connection.cancel() })
    }
}
