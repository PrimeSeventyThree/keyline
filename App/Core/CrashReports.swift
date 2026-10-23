import Foundation
import MetricKit
import os

/// A crash, summarised from a MetricKit diagnostic: what happened and where, without any
/// user data.
struct CrashReport: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var appVersion: String
    var osVersion: String
    /// Exception, signal and termination reason, one per line.
    var reason: String
    /// The crashed thread's top frames, innermost first, as "binary +offset".
    var frames: [String]

    /// Builds a report from `MXCrashDiagnostic.jsonRepresentation()`.
    init?(diagnosticJSON data: Data, date: Date) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let meta = root["diagnosticMetaData"] as? [String: Any] ?? [:]
        self.date = date
        appVersion = meta["appVersion"] as? String ?? "?"
        osVersion = meta["osVersion"] as? String ?? "?"
        reason = [
            (meta["exceptionType"]).map { "Exception type: \($0)" },
            (meta["exceptionCode"]).map { "Exception code: \($0)" },
            (meta["signal"]).map { "Signal: \($0)" },
            (meta["terminationReason"] as? String).map { "Termination: \($0)" },
        ].compactMap { $0 }.joined(separator: "\n")
        frames = Self.crashedThreadFrames(root["callStackTree"] as? [String: Any] ?? [:], limit: 20)
    }

    /// MetricKit nests each frame's caller in `subFrames`; walk the attributed (crashed)
    /// thread from the innermost frame outwards.
    static func crashedThreadFrames(_ tree: [String: Any], limit: Int) -> [String] {
        let stacks = tree["callStacks"] as? [[String: Any]] ?? []
        let crashed = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        var frame = (crashed?["callStackRootFrames"] as? [[String: Any]])?.first
        var frames: [String] = []
        while let current = frame, frames.count < limit {
            let binary = current["binaryName"] as? String ?? "???"
            let offset = current["offsetIntoBinaryTextSegment"].map { "\($0)" } ?? "?"
            frames.append("\(binary) +\(offset)")
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        return frames
    }
}

/// Receives crash diagnostics from MetricKit (macOS delivers them at a later launch, usually
/// within a day), keeps the latest ones on this Mac, and turns them into a GitHub issue the
/// user reviews before sending. Nothing is sent automatically.
@MainActor
final class CrashReportStore: NSObject, ObservableObject {
    static let limit = 10
    static let issuesURL = URL(string: "https://github.com/PrimeSeventyThree/keyline/issues/new")!

    @Published private(set) var reports: [CrashReport] = []
    private let fileURL: URL
    private let log = Logger.keyline("crash-reports")

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([CrashReport].self, from: data) {
            reports = saved
        }
    }

    /// `crash-reports.json` in the app's Application Support folder.
    static func standard() -> CrashReportStore {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            .map { $0.appendingPathComponent(KeylineIdentifiers.app, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return CrashReportStore(fileURL: folder.appendingPathComponent("crash-reports.json"))
    }

    func startListening() {
        MXMetricManager.shared.add(self)
    }

    func add(_ new: [CrashReport]) {
        guard !new.isEmpty else { return }
        reports = Array((new + reports).sorted { $0.date > $1.date }.prefix(Self.limit))
        save()
    }

    func deleteAll() {
        reports = []
        save()
    }

    private func save() {
        do {
            try JSONEncoder().encode(reports).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to save crash reports: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A new GitHub issue pre-filled with `description`, this Mac's versions and, if asked, the
    /// crash reports. GitHub limits URL length, so frames are trimmed to fit.
    static func issueURL(description: String, reports: [CrashReport], appVersion: String, osVersion: String) -> URL {
        let title = reports.isEmpty
            ? "Report: \(description.split(separator: "\n").first.map(String.init)?.prefix(60) ?? "Keyline feedback")"
            : "Crash: \(reports[0].reason.split(separator: "\n").first.map(String.init) ?? "Keyline quit unexpectedly")"
        var frameLimit = 20
        var url: URL
        repeat {
            var body = "### What happened\n\(description.isEmpty ? "_No description._" : description)\n\n"
            body += "### Environment\n- Keyline \(appVersion)\n- macOS \(osVersion)\n"
            for (index, report) in reports.enumerated() {
                body += "\n### Crash \(index + 1) of \(reports.count) – \(ISO8601DateFormatter().string(from: report.date))\n"
                body += "Keyline \(report.appVersion), \(report.osVersion)\n```\n\(report.reason)\n"
                body += report.frames.prefix(frameLimit).joined(separator: "\n") + "\n```\n"
            }
            var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "title", value: String(title)), URLQueryItem(name: "body", value: body)]
            url = components.url!
            frameLimit -= 5
        } while url.absoluteString.count > 7_500 && frameLimit > 0
        return url
    }
}

extension CrashReportStore: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).compactMap { CrashReport(diagnosticJSON: $0.jsonRepresentation(), date: payload.timeStampEnd) }
        }
        Task { @MainActor in self.add(reports) }
    }
}
