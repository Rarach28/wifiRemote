// helper/remote.py, the Python side that holds the ADB connection. Only the agent (Agent.swift) starts it.
import Foundation



/// Talks to helper/remote.py over stdin/stdout. Commands run one at a time on a private queue.
final class Helper: @unchecked Sendable {
    private let queue = DispatchQueue(label: "remote.helper")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()

    private func start() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: BuildConfig.python)
        p.arguments = ["-I", BuildConfig.repo + "/helper/remote.py"]
        var env = ProcessInfo.processInfo.environment
        env["TV_HOST"] = Store.activeHost.isEmpty ? "0.0.0.0" : Store.activeHost
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p
        input = inPipe.fileHandleForWriting
        output = outPipe.fileHandleForReading
        buffer = Data()
    }

    func restart() {
        queue.async { self.process?.terminate(); self.process = nil }
    }

    private func readLine() -> Data? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer = Data(buffer[(nl + 1)...])
                return Data(line)
            }
            guard let chunk = output?.availableData, !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
    }

    /// Sends one command; the reply (parsed JSON, or nil on failure) arrives on the main queue.
    func send(_ command: String, done: @escaping @Sendable (Any?) -> Void = { _ in }) {
        queue.async {
            var reply: Any?
            for _ in 0..<2 {
                do {
                    if self.process?.isRunning != true { try self.start() }
                    self.input?.write((command + "\n").data(using: .utf8)!)
                    if let line = self.readLine() {
                        reply = try? JSONSerialization.jsonObject(with: line)
                        break
                    }
                } catch {}
                self.process?.terminate()
                self.process = nil
            }
            let result = reply
            DispatchQueue.main.async { done(result) }
        }
    }
}

