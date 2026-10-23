import SwiftUI

/// The licence texts bundled from Resources/Licenses (see scripts/update-licenses.sh).
struct LicensesSheet: View {
    var onDone: () -> Void = {}

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    private static let titles = [
        "keyline-notice": "Keyline",
        "apache-2.0": "Apache License 2.0 (Keyline, Outline)",
        "flag-icons": "flag-icons (MIT)",
        "db-ip": "DB-IP IP to Country Lite (CC BY 4.0)",
        "go-modules": "Network core: Go modules and lwIP",
    ]

    /// Files named license-<order>-<name>.txt, in order.
    private var entries: [Entry] {
        let urls = Bundle.keylineResources.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("license-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                    .split(separator: "-", maxSplits: 2).dropFirst(2).joined()
                return Entry(id: name, title: Self.titles[name] ?? name, text: text)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "licenses", defaultValue: "Licenses"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(String(localized: "done", defaultValue: "Done"), action: onDone)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .background(Theme.background)
    }
}
