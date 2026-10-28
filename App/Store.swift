// The saved TVs and each TV's app buttons, in the app's UserDefaults. The window writes them; the agent (same
// bundle, so the same defaults) reads them to tell the widgets which buttons to draw.
import Foundation

struct SavedTv: Codable, Identifiable, Hashable {
    /// The TV's IP address (or host name); also its identity in the app.
    var host: String
    var name: String
    /// 5555 for classic network debugging. With wireless debugging (tls) the TV picks a new port now and then;
    /// the agent finds it again over mDNS and saves it here.
    var port: Int = 5555
    var tls: Bool = false
    var id: String { host }
    var serial: String { "\(host):\(port)" }

    init(host: String, name: String, port: Int = 5555, tls: Bool = false) {
        self.host = host
        self.name = name
        self.port = port
        self.tls = tls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        name = try c.decode(String.self, forKey: .name)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 5555
        tls = try c.decodeIfPresent(Bool.self, forKey: .tls) ?? false
    }
}

struct AppButtonItem: Codable, Identifiable, Hashable {
    var package: String
    var name: String
    var id: String { package }
}

enum Store {
    private static let defaults = UserDefaults.standard

    static var tvs: [SavedTv] {
        get { decode("tvs") ?? [] }
        set { encode(newValue, "tvs") }
    }

    static var activeHost: String {
        get { defaults.string(forKey: "activeTv") ?? tvs.first?.host ?? "" }
        set { defaults.set(newValue, forKey: "activeTv") }
    }

    static var activeTv: SavedTv? { tvs.first { $0.host == activeHost } }

    static func buttons(for host: String) -> [AppButtonItem] {
        decode("buttons." + host) ?? []
    }

    static func setButtons(_ items: [AppButtonItem], for host: String) { encode(items, "buttons." + host) }

    /// Saves a changed TV (the agent's new port for a wireless-debugging TV, a new name).
    static func update(_ tv: SavedTv) {
        var list = tvs
        if let i = list.firstIndex(where: { $0.host == tv.host }) { list[i] = tv } else { list.append(tv) }
        tvs = list
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        defaults.synchronize()   // the agent reads what the window wrote a moment ago
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
        defaults.synchronize()
    }
}
