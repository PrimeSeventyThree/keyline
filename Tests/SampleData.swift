import Foundation

/// Made-up servers and stats for design snapshots. Addresses are from documentation ranges.
enum SampleData {
    static let toronto = ServerSummary(id: "1", name: "Home", country: Country(code: "CA"),
                                       address: "203.0.113.24:6328", isDynamic: false)
    static let newYork = ServerSummary(id: "2", name: "Office", country: Country(code: "US"),
                                       address: "198.51.100.7:443", isDynamic: true)
    static let berlin = ServerSummary(id: "3", name: "Berlin", country: Country(code: "DE"),
                                      address: "192.0.2.80:8388", isDynamic: false)
    static let tokyo = ServerSummary(id: "4", name: "Tokyo", country: Country(code: "JP"),
                                     address: "192.0.2.15:8388", isDynamic: false)
    static let unknown = ServerSummary(id: "5", name: "keys.example.com", country: nil,
                                       address: "", isDynamic: true)
    static let servers = [toronto, newYork, berlin, tokyo, unknown]

    /// A wavy series that ends at `last`, for the speed and latency charts.
    static func series(count: Int = 60, base: Double, swing: Double, last: Double, phase: Double = 0) -> [Double] {
        (0..<count).map { (i: Int) -> Double in
            guard i < count - 1 else { return last }
            let x = Double(i)
            let slow: Double = swing * sin(x / 6 + phase)
            let fast: Double = swing * 0.35 * sin(x / 2.3)
            return max(0, base + slow + fast)
        }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static var connected: ConnectScreenState {
        ConnectScreenState(
            phase: .connected, server: toronto, recentServers: [toronto, newYork, berlin, tokyo, unknown],
            connectedSince: now.addingTimeInterval(-(45 * 60 + 29)), now: now,
            download: series(base: 5_200_000, swing: 1_400_000, last: 5_912_500),
            upload: series(base: 2_100_000, swing: 600_000, last: 2_337_500, phase: 1.3),
            latency: series(count: 20, base: 22, swing: 6, last: 18, phase: 0.6),
            totals: TrafficStats(bytesSent: 412_000_000, bytesReceived: 1_920_000_000))
    }

    static var disconnected: ConnectScreenState {
        ConnectScreenState(phase: .disconnected, server: toronto, recentServers: [toronto, newYork, berlin, tokyo, unknown], now: now)
    }

    static var connecting: ConnectScreenState {
        var state = disconnected
        state.phase = .connecting
        state.server = newYork
        return state
    }
}
