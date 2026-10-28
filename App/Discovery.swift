// Finds Android TVs with network debugging on: every address of this Mac's local /24 networks that accepts
// a TCP connection on the ADB port 5555.
import Darwin
import Foundation
import Network

enum Discovery {
    static func localPrefixes() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (Int32(ifa.ifa_flags) & IFF_LOOPBACK) == 0, (Int32(ifa.ifa_flags) & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let octets = ip.split(separator: ".")
            // Private ranges only: never sweep a public network.
            guard octets.count == 4, ip.hasPrefix("192.168.") || ip.hasPrefix("10.")
                    || (ip.hasPrefix("172.") && (16...31).contains(Int(octets[1]) ?? 0)) else { continue }
            let prefix = octets.prefix(3).joined(separator: ".")
            if !result.contains(prefix) { result.append(prefix) }
        }
        return result
    }

    /// The addresses that answered on port 5555, sorted.
    static func scan() async -> [String] {
        let hosts = localPrefixes().flatMap { p in (1...254).map { "\(p).\($0)" } }
        return await withTaskGroup(of: String?.self) { group in
            for host in hosts { group.addTask { await probe(host) ? host : nil } }
            var found: [String] = []
            for await host in group { if let host { found.append(host) } }
            return found.sorted { $0.split(separator: ".").last.flatMap { Int($0) } ?? 0
                < $1.split(separator: ".").last.flatMap { Int($0) } ?? 0 }
        }
    }

    private static func probe(_ host: String) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: 5555, using: .tcp)
            let lock = NSLock()
            var done = false
            func finish(_ ok: Bool) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting: finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { finish(false) }
        }
    }
}
