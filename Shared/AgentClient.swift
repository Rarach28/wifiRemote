// Shared by the app and the widget: one HTTP call to the Remote agent, which listens on 127.0.0.1 only and
// answers nobody without the token baked into this build (BuildConfig, written by build.sh).
import Foundation

enum AgentClient {
    /// GETs a path such as "/key/home" and returns the parsed JSON reply, or nil when the agent is not
    /// running or the TV did not answer.
    static func get(_ path: String, timeout: TimeInterval = 20) async -> Any? {
        guard let url = URL(string: "http://127.0.0.1:\(BuildConfig.agentPort)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(BuildConfig.agentToken, forHTTPHeaderField: "X-Token")
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func ok(_ reply: Any?) -> Bool { (reply as? [String: Any])?["ok"] as? Bool == true }

    /// App buttons as (package, name) pairs, in button order.
    static func apps(_ reply: Any?) -> [(String, String)] {
        (reply as? [[String]] ?? []).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
}

/// Brand colour behind each dock app's button.
func brandRGB(for package: String) -> (Double, Double, Double) {
    switch package {
    case "com.netflix.ninja": return (0.90, 0.04, 0.08)
    case "com.google.android.youtube.tv": return (0.85, 0.05, 0.05)
    case "net.cme.voyo.cz.tvapp": return (0.36, 0.27, 0.85)
    case "org.xbmc.kodi": return (0.12, 0.64, 0.88)
    case "com.skyshowtime.skyshowtime.google": return (0.62, 0.18, 0.78)
    case "tv.poda.tv": return (0.95, 0.45, 0.20)
    case "com.spotify.tv.android": return (0.11, 0.73, 0.33)
    default: return (0.5, 0.5, 0.5)
    }
}
