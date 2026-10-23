import XCTest

@MainActor
final class StatsSamplerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testSpeedsComeFromTheChangeBetweenSamples() {
        let sampler = StatsSampler()
        sampler.sample(TrafficStats(bytesSent: 1_000, bytesReceived: 10_000), at: start)
        XCTAssertEqual(sampler.download, [], "the first sample has nothing to compare with")
        XCTAssertEqual(sampler.totals.bytesReceived, 10_000)

        sampler.sample(TrafficStats(bytesSent: 3_000, bytesReceived: 30_000), at: start.addingTimeInterval(2))
        XCTAssertEqual(sampler.download, [10_000], "20 000 bytes over 2 s")
        XCTAssertEqual(sampler.upload, [1_000])
        XCTAssertEqual(sampler.totals.bytesSent, 3_000)
    }

    func testCounterResetCountsFromZero() {
        let sampler = StatsSampler()
        sampler.sample(TrafficStats(bytesSent: 5_000, bytesReceived: 50_000), at: start)
        sampler.sample(TrafficStats(bytesSent: 100, bytesReceived: 400), at: start.addingTimeInterval(1))
        XCTAssertEqual(sampler.download, [400], "a restarted tunnel never shows a negative speed")
        XCTAssertEqual(sampler.upload, [100])
    }

    func testSamplesAtTheSameTimeAreIgnored() {
        let sampler = StatsSampler()
        sampler.sample(TrafficStats(bytesSent: 0, bytesReceived: 0), at: start)
        sampler.sample(TrafficStats(bytesSent: 10, bytesReceived: 10), at: start)
        XCTAssertEqual(sampler.download, [])
    }

    func testHistoryIsCapped() {
        let sampler = StatsSampler()
        for second in 0...(StatsSampler.speedHistory + 10) {
            sampler.sample(TrafficStats(bytesSent: 0, bytesReceived: UInt64(second * 100)), at: start.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(sampler.download.count, StatsSampler.speedHistory)

        for value in 0..<(StatsSampler.latencyHistory + 5) {
            sampler.recordLatency(LatencySample(milliseconds: Double(value)))
        }
        XCTAssertEqual(sampler.latency.count, StatsSampler.latencyHistory)
        XCTAssertEqual(sampler.latency.last, Double(StatsSampler.latencyHistory + 4), "the newest value is last")
    }

    func testStopClearsEverything() {
        let sampler = StatsSampler()
        sampler.sample(TrafficStats(bytesSent: 0, bytesReceived: 0), at: start)
        sampler.sample(TrafficStats(bytesSent: 10, bytesReceived: 10), at: start.addingTimeInterval(1))
        sampler.recordLatency(LatencySample(milliseconds: 20))
        sampler.stop()
        XCTAssertEqual(sampler.download, [])
        XCTAssertEqual(sampler.latency, [])
        XCTAssertEqual(sampler.totals, TrafficStats())

        sampler.sample(TrafficStats(bytesSent: 500, bytesReceived: 500), at: start.addingTimeInterval(5))
        XCTAssertEqual(sampler.download, [], "after a stop, the next sample starts a new series")
    }

    func testPollingReadsFromTheSource() async throws {
        final class Source: TunnelStatsSource {
            var received: UInt64 = 0
            func trafficStats() async -> TrafficStats? {
                received += 1_000
                return TrafficStats(bytesSent: 0, bytesReceived: received)
            }
            func latency() async -> LatencySample? { LatencySample(milliseconds: 42) }
        }
        let sampler = StatsSampler()
        sampler.start(source: Source())
        defer { sampler.stop() }
        for _ in 0..<40 where sampler.download.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(sampler.download.isEmpty, "polling produced a speed sample")
        XCTAssertEqual(sampler.latency, [42], "latency is measured right away, then every 30 s")
    }
}

@MainActor
final class ServerSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let servers = ["a", "b", "c", "d", "e", "f"].map { Server(id: $0, name: $0.uppercased(), kind: .static, address: "") }

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "keyline-tests-\(UUID().uuidString)")
    }

    func testRecentServersAreMostRecentFirstAndCapped() {
        let selection = ServerSelection(defaults: defaults)
        for id in ["a", "b", "c", "a", "d", "e", "f"] { selection.recordConnection(to: id) }
        XCTAssertEqual(selection.recentIDs, ["f", "e", "d", "a", "c"])
        XCTAssertEqual(selection.selectedID, "f")
    }

    func testSelectionSurvivesRelaunch() {
        ServerSelection(defaults: defaults).recordConnection(to: "c")
        let relaunched = ServerSelection(defaults: defaults)
        XCTAssertEqual(relaunched.selectedID, "c")
        XCTAssertEqual(relaunched.recentIDs, ["c"])
    }

    func testResolvedServerFallsBack() {
        let selection = ServerSelection(defaults: defaults)
        XCTAssertEqual(selection.resolvedServer(in: servers)?.id, "a", "nothing chosen: the first server")
        selection.recordConnection(to: "c")
        selection.select("gone")
        XCTAssertEqual(selection.resolvedServer(in: servers)?.id, "c", "a forgotten selection falls back to the most recent")
        XCTAssertNil(selection.resolvedServer(in: []))
    }

    func testRecentStripIsToppedUpFromTheList() {
        let selection = ServerSelection(defaults: defaults)
        selection.recordConnection(to: "d")
        XCTAssertEqual(selection.recentServers(in: servers).map(\.id), ["d", "a", "b", "c", "e"])
    }
}
