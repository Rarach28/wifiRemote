// The saved TVs and each TV's app buttons, in the app's UserDefaults. The window writes them; the agent (same
// bundle, so the same defaults) reads them to tell the widgets which buttons to draw.
import Foundation

struct SavedTv: Codable, Identifiable, Hashable {
    var host: String
    var name: String
    var id: String { host }
}

struct AppButtonItem: Codable, Identifiable, Hashable {
    var package: String
    var name: String
    var id: String { package }
}

enum Store {
    private static let defaults = UserDefaults.standard

    static var tvs: [SavedTv] {
        get { decode("tvs") ?? seedTvs() }
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

    /// First run: the TV the app was built for, if any.
    private static func seedTvs() -> [SavedTv] {
        BuildConfig.tvHost.isEmpty ? [] : [SavedTv(host: BuildConfig.tvHost, name: "TV")]
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
