import XCTest

@MainActor
final class CrashReportTests: XCTestCase {
    /// Shaped like `MXCrashDiagnostic.jsonRepresentation()`.
    private let diagnostic = Data("""
    {
      "callStackTree": {
        "callStackPerThread": true,
        "callStacks": [
          { "threadAttributed": false,
            "callStackRootFrames": [ { "binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 1 } ] },
          { "threadAttributed": true,
            "callStackRootFrames": [
              { "binaryName": "Keyline", "offsetIntoBinaryTextSegment": 1234,
                "subFrames": [ { "binaryName": "SwiftUI", "offsetIntoBinaryTextSegment": 99,
                                 "subFrames": [ { "binaryName": "AppKit", "offsetIntoBinaryTextSegment": 7 } ] } ] } ] }
        ]
      },
      "diagnosticMetaData": {
        "appVersion": "0.1.0", "osVersion": "macOS 15.7.9 (24G830)",
        "exceptionType": 1, "exceptionCode": 0, "signal": 11,
        "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11"
      }
    }
    """.utf8)

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesTheCrashedThread() throws {
        let report = try XCTUnwrap(CrashReport(diagnosticJSON: diagnostic, date: date))
        XCTAssertEqual(report.appVersion, "0.1.0")
        XCTAssertEqual(report.osVersion, "macOS 15.7.9 (24G830)")
        XCTAssertEqual(report.frames, ["Keyline +1234", "SwiftUI +99", "AppKit +7"], "the attributed thread, innermost first")
        XCTAssertTrue(report.reason.contains("Signal: 11"))
        XCTAssertTrue(report.reason.contains("Segmentation fault"))
    }

    func testRejectsNonJSON() {
        XCTAssertNil(CrashReport(diagnosticJSON: Data("nope".utf8), date: date))
    }

    func testIssueURLCarriesTheReport() throws {
        let report = try XCTUnwrap(CrashReport(diagnosticJSON: diagnostic, date: date))
        let url = CrashReportStore.issueURL(description: "It crashed when I switched servers.", reports: [report],
                                            appVersion: "0.1.0 (12)", osVersion: "15.7.9")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let title = try XCTUnwrap(items.first { $0.name == "title" }?.value)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/PrimeSeventyThree/keyline/issues/new"))
        XCTAssertTrue(title.hasPrefix("Crash: "))
        XCTAssertTrue(body.contains("It crashed when I switched servers."))
        XCTAssertTrue(body.contains("Keyline 0.1.0 (12)"))
        XCTAssertTrue(body.contains("Keyline +1234"))
    }

    func testIssueURLWithoutCrashesIsFeedback() throws {
        let url = CrashReportStore.issueURL(description: "Feature idea", reports: [], appVersion: "0.1.0", osVersion: "15.0")
        let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "title" }?.value
        XCTAssertEqual(title, "Report: Feature idea")
    }

    func testLongReportsAreTrimmedToFitAURL() throws {
        var report = try XCTUnwrap(CrashReport(diagnosticJSON: diagnostic, date: date))
        report.frames = (0..<20).map { "SomeVeryLongFrameworkNameForTesting.framework/Versions/A/Binary +\($0 * 123_456)" }
        let url = CrashReportStore.issueURL(description: String(repeating: "x", count: 500),
                                            reports: Array(repeating: report, count: 5), appVersion: "0.1.0", osVersion: "15.0")
        XCTAssertLessThanOrEqual(url.absoluteString.count, 7_500)
    }

    func testStoreKeepsTheLatestReports() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let base = try XCTUnwrap(CrashReport(diagnosticJSON: diagnostic, date: date))
        let store = CrashReportStore(fileURL: file)
        store.add((0..<12).map { offset in var report = base; report.id = UUID(); report.date = date.addingTimeInterval(Double(offset)); return report })
        XCTAssertEqual(store.reports.count, CrashReportStore.limit)
        XCTAssertEqual(store.reports.first?.date, date.addingTimeInterval(11), "newest first")

        XCTAssertEqual(CrashReportStore(fileURL: file).reports.count, CrashReportStore.limit, "saved across launches")
        store.deleteAll()
        XCTAssertEqual(CrashReportStore(fileURL: file).reports, [])
    }
}
