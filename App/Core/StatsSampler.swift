import Foundation

/// Where `StatsSampler` reads from: the running tunnel, or a fake in tests.
@MainActor
protocol TunnelStatsSource: AnyObject {
    func trafficStats() async -> TrafficStats?
    func latency() async -> LatencySample?
}

extension TunnelController: TunnelStatsSource {}

/// Turns the extension's byte counters into speeds for the charts, and keeps recent latency
/// measurements. `start()` polls traffic every second and latency every 30 seconds while
/// connected; `sample(...)` and `recordLatency(...)` do one step each, for tests.
@MainActor
final class StatsSampler: ObservableObject {
    static let speedHistory = 60
    static let latencyHistory = 20
    static let latencyInterval: TimeInterval = 30

    /// Bytes per second, oldest first, one per sample.
    @Published private(set) var download: [Double] = []
    @Published private(set) var upload: [Double] = []
    /// Milliseconds, oldest first.
    @Published private(set) var latency: [Double] = []
    @Published private(set) var totals = TrafficStats()

    private var previous: (stats: TrafficStats, time: Date)?
    private var lastLatencyCheck: Date?
    private var task: Task<Void, Never>?

    func start(source: TunnelStatsSource) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                if let stats = await source.trafficStats() {
                    self.sample(stats, at: now)
                }
                if self.lastLatencyCheck.map({ now.timeIntervalSince($0) >= Self.latencyInterval }) ?? true {
                    self.lastLatencyCheck = now
                    if let sample = await source.latency() {
                        self.recordLatency(sample)
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Stops polling and clears everything, for the next connection. Publishes only if there
    /// was something to clear, so calling it while stopped doesn't update the window.
    func stop() {
        task?.cancel()
        task = nil
        previous = nil
        lastLatencyCheck = nil
        if !download.isEmpty { download = [] }
        if !upload.isEmpty { upload = [] }
        if !latency.isEmpty { latency = [] }
        if totals != TrafficStats() { totals = TrafficStats() }
    }

    /// Adds speeds computed from the change since the previous sample.
    func sample(_ stats: TrafficStats, at time: Date) {
        defer {
            previous = (stats, time)
            totals = stats
        }
        guard let previous else { return }
        let seconds = time.timeIntervalSince(previous.time)
        guard seconds > 0 else { return }
        // Counters only go down when the tunnel restarted; count from zero then.
        let received = stats.bytesReceived >= previous.stats.bytesReceived
            ? stats.bytesReceived - previous.stats.bytesReceived : stats.bytesReceived
        let sent = stats.bytesSent >= previous.stats.bytesSent
            ? stats.bytesSent - previous.stats.bytesSent : stats.bytesSent
        append(Double(received) / seconds, to: &download, limit: Self.speedHistory)
        append(Double(sent) / seconds, to: &upload, limit: Self.speedHistory)
    }

    func recordLatency(_ sample: LatencySample) {
        append(sample.milliseconds, to: &latency, limit: Self.latencyHistory)
    }

    private func append(_ value: Double, to series: inout [Double], limit: Int) {
        series.append(value)
        if series.count > limit { series.removeFirst(series.count - limit) }
    }
}
