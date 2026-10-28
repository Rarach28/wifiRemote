// The official adb from Android SDK Platform-Tools: one already on this Mac (Homebrew, Android Studio), or
// Google's own download, fetched once into Application Support. adb handles both kinds of TV connection:
// classic network debugging on port 5555, and Android 11+ wireless debugging (TLS, paired with a code).
import Foundation

final class Adb: @unchecked Sendable {
    static let shared = Adb()

    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/WiFi Remote")
    private static let downloadURL = URL(string: "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")!

    private var path: String?

    private func locate() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            Self.supportDir.appending(path: "platform-tools/adb").path,
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            home + "/Library/Android/sdk/platform-tools/adb",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The adb binary, downloading Platform-Tools first if this Mac has none. Blocking; call off the main queue.
    func binary() throws -> String {
        if let path { return path }
        if let found = locate() { path = found; return found }
        try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let zip = Self.supportDir.appending(path: "platform-tools.zip")
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        URLSession.shared.downloadTask(with: Self.downloadURL) { tmp, response, error in
            defer { done.signal() }
            guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                failure = error ?? URLError(.badServerResponse)
                return
            }
            try? FileManager.default.removeItem(at: zip)
            do { try FileManager.default.moveItem(at: tmp, to: zip) } catch { failure = error }
        }.resume()
        done.wait()
        if let failure { throw failure }
        try? FileManager.default.removeItem(at: Self.supportDir.appending(path: "platform-tools"))
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, Self.supportDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        try? FileManager.default.removeItem(at: zip)
        guard let found = locate() else { throw URLError(.cannotDecodeContentData) }
        path = found
        return found
    }

    var isReady: Bool { path != nil || locate() != nil }

    /// Runs adb with these arguments; stdout and stderr together. Status -1: it could not run or timed out.
    func run(_ args: [String], timeout: TimeInterval = 20) -> (status: Int32, out: String) {
        guard let adb = try? binary() else { return (-1, "adb unavailable") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        // Read on another thread: a full pipe would otherwise stall adb before it exits.
        var data = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        if read.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return (-1, "timed out")
        }
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The state adb reports for a serial ("device", "unauthorized", "offline"), or nil if it is not listed.
    func state(of serial: String) -> String? {
        for line in run(["devices"], timeout: 10).out.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count >= 2, parts[0] == serial { return String(parts[1]) }
        }
        return nil
    }

    struct Service {
        let type: String   // "_adb._tcp", "_adb-tls-connect._tcp" or "_adb-tls-pairing._tcp"
        let host: String
        let port: Int
    }

    /// TVs announcing themselves on the network (mDNS), as adb sees them.
    func services() -> [Service] {
        run(["mdns", "services"], timeout: 10).out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let type = parts[1].hasSuffix(".") ? String(parts[1].dropLast()) : parts[1]
            guard type.hasPrefix("_adb"), let colon = parts[2].lastIndex(of: ":"),
                  let port = Int(parts[2][parts[2].index(after: colon)...]) else { return nil }
            return Service(type: type, host: String(parts[2][..<colon]), port: port)
        }
    }
}
