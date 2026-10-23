import XCTest

final class StatsFormatTests: XCTestCase {
    func testSpeedsAreInBitsPerSecond() {
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 5_912_500).value, "47.3")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 5_912_500).unit, "Mbps")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 102_500).unit, "kbps")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 102_500).value, "820")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 200_000_000).unit, "Gbps")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 0).value, "0")
        XCTAssertEqual(StatsFormat.speed(bytesPerSecond: 0).unit, "bps")
    }

    func testDurations() {
        XCTAssertEqual(StatsFormat.duration(0), "00:00:00")
        XCTAssertEqual(StatsFormat.duration(45 * 60 + 29), "00:45:29")
        XCTAssertEqual(StatsFormat.duration(26 * 3600 + 61), "26:01:01", "hours keep counting past a day")
        XCTAssertEqual(StatsFormat.duration(-5), "00:00:00", "clock changes never show negative time")
    }

    func testByteTotalsUseDigits() {
        XCTAssertFalse(StatsFormat.bytes(0).contains("Zero"))
        XCTAssertTrue(StatsFormat.bytes(0).hasPrefix("0"))
        XCTAssertTrue(StatsFormat.bytes(1_920_000_000).contains("GB"))
    }

    func testRecentServersPutTheSelectedOneInTheMiddle() {
        let ids = RecentServersStrip.arranged(SampleData.servers, selectedID: SampleData.toronto.id).map(\.id)
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(ids[2], SampleData.toronto.id)
        XCTAssertEqual(RecentServersStrip.arranged(SampleData.servers, selectedID: nil).map(\.id),
                       SampleData.servers.map(\.id), "no selection keeps the order")
    }
}
