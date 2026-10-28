// What the app, its agent and the sandboxed widgets must agree on: the agent's port and a random token, kept in
// the app group's defaults. The token is made on first launch, so every install has its own.
import Foundation

enum SharedConfig {
    /// "<team>.io.github.rarach28.wifiremote", from Info.plist (AppGroup), which build settings fill in.
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""
    static let defaults = UserDefaults(suiteName: groupID) ?? .standard
    static let defaultPort: UInt16 = 47_830

    static var port: UInt16 {
        get { UInt16(exactly: defaults.integer(forKey: "agentPort")).flatMap { $0 == 0 ? nil : $0 } ?? defaultPort }
        set { defaults.set(Int(newValue), forKey: "agentPort") }
    }

    /// The token the agent wants on every request. Created by whichever of the app or the agent runs first.
    static var token: String {
        if let token = defaults.string(forKey: "agentToken"), !token.isEmpty { return token }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: "agentToken")
        return token
    }
}
