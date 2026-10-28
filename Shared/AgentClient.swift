// Shared by the app and the widgets: one HTTP call to the WiFi Remote agent, which listens on 127.0.0.1 only and
// answers nobody without the install's token (SharedConfig).
import Foundation

enum AgentClient {
    /// GETs a path such as "/key/home" and returns the parsed JSON reply, or nil when the agent is not
    /// running or the TV did not answer.
    static func get(_ path: String, timeout: TimeInterval = 20) async -> Any? {
        let (code, json) = await call(path, timeout: timeout)
        return code == 200 ? json : nil
    }

    /// The status code (0: no answer) and the JSON body, errors included.
    static func call(_ path: String, timeout: TimeInterval = 20) async -> (Int, Any?) {
        guard let url = URL(string: "http://127.0.0.1:\(SharedConfig.port)\(path)") else { return (0, nil) }
        var request = URLRequest(url: url)
        request.setValue(SharedConfig.token, forHTTPHeaderField: "X-Token")
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (0, nil) }
        return (http.statusCode, try? JSONSerialization.jsonObject(with: data))
    }

    static func ok(_ reply: Any?) -> Bool { (reply as? [String: Any])?["ok"] as? Bool == true }

    static func error(_ reply: Any?) -> String? { (reply as? [String: Any])?["error"] as? String }

    /// App buttons as (package, name) pairs, in button order.
    static func apps(_ reply: Any?) -> [(String, String)] {
        (reply as? [[String]] ?? []).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
}

/// Brand colour behind each app's button.
func brandRGB(for package: String) -> (Double, Double, Double) {
    switch package {
    case "com.netflix.ninja": return (0.90, 0.04, 0.08)
    case "com.google.android.youtube.tv": return (0.85, 0.05, 0.05)
    case "net.cme.voyo.cz.tvapp": return (0.36, 0.27, 0.85)
    case "org.xbmc.kodi": return (0.12, 0.64, 0.88)
    case "com.skyshowtime.skyshowtime.google": return (0.62, 0.18, 0.78)
    case "tv.poda.tv": return (0.95, 0.45, 0.20)
    case "com.spotify.tv.android": return (0.11, 0.73, 0.33)
    case "com.amazon.amazonvideo.livingroom": return (0.0, 0.66, 0.88)
    case "com.disney.disneyplus": return (0.07, 0.20, 0.55)
    case "com.wbd.stream", "com.hbo.hbonow": return (0.35, 0.18, 0.85)
    case "com.apple.atve.androidtv.appletv": return (0.2, 0.2, 0.22)
    case "com.plexapp.android": return (0.90, 0.63, 0.05)
    case "org.jellyfin.androidtv": return (0.55, 0.30, 0.85)
    default: return (0.42, 0.45, 0.55)
    }
}
