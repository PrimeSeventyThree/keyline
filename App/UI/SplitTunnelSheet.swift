import SwiftUI

/// Edits split tunneling: the mode, the local network switch and the list of destinations.
struct SplitTunnelSheet: View {
    @Binding var settings: SplitTunnelSettings
    var onDone: () -> Void = {}

    @State private var newEntry = ""
    @State private var entryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "split-tunneling", defaultValue: "Split tunneling"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            SegmentedChoice(options: SplitTunnelSettings.Mode.allCases, selection: $settings.mode, title: Self.title)
            Text(Self.explanation(settings.mode))
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $settings.bypassLocalNetwork) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "split-local-network", defaultValue: "Bypass local network"))
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textPrimary)
                    Text(String(localized: "split-local-network-detail",
                                defaultValue: "Reach printers, your router and other devices at home or work directly."))
                        .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                }
            }
            .toggleStyle(KeylineToggleStyle())

            if settings.mode != .off {
                entryEditor
            }

            HStack {
                Spacer()
                Button(String(localized: "done", defaultValue: "Done"), action: onDone)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
    }

    private var entryEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ThemedTextField(placeholder: String(localized: "split-entry-placeholder",
                                                    defaultValue: "203.0.113.7, 10.0.0.0/8 or example.com"),
                                text: $newEntry, isInvalid: entryError != nil, onSubmit: addEntry)
                Button(String(localized: "add", defaultValue: "Add"), action: addEntry)
                    .buttonStyle(KeylineButtonStyle())
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let entryError {
                Text(entryError).font(.system(size: 12)).foregroundColor(Theme.danger)
            }
            if settings.entries.isEmpty {
                Text(String(localized: "split-empty", defaultValue: "Nothing listed yet."))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            } else if settings.entries.count <= 6 {
                entryList
            } else {
                ScrollView { entryList }
                    .frame(height: 230)
            }
            Text(String(localized: "split-domains-note",
                        defaultValue: "Domains are looked up when you connect and every 10 minutes. Add each host name you need, such as www.example.com. Sites that change addresses often, like large CDNs, may not always match."))
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var entryList: some View {
        VStack(spacing: 6) {
            ForEach(settings.entries, id: \.self) { entry in
                entryRow(entry)
            }
        }
    }

    private func entryRow(_ entry: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: SplitTunnelEntry(entry).map { if case .domain = $0 { return "globe" } else { return "number" } } ?? "questionmark")
                .foregroundColor(Theme.accent)
                .frame(width: 18)
            Text(entry)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button {
                settings.entries.removeAll { $0 == entry }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "split-remove", defaultValue: "Remove \(entry)")))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
    }

    private func addEntry() {
        guard let entry = SplitTunnelEntry(newEntry) else {
            entryError = String(localized: "split-entry-invalid",
                                defaultValue: "Enter an IPv4 address, a subnet like 10.0.0.0/8, or a domain like example.com.")
            return
        }
        let text: String
        switch entry {
        case .subnet(let subnet): text = subnet.prefix == 32 ? subnet.address : subnet.cidr
        case .domain(let name): text = name
        }
        if !settings.entries.contains(text) { settings.entries.append(text) }
        newEntry = ""
        entryError = nil
    }

    static func title(_ mode: SplitTunnelSettings.Mode) -> String {
        switch mode {
        case .off: return String(localized: "split-mode-off", defaultValue: "Off")
        case .exclude: return String(localized: "split-mode-exclude", defaultValue: "Exclude listed")
        case .include: return String(localized: "split-mode-include", defaultValue: "Only listed")
        }
    }

    static func explanation(_ mode: SplitTunnelSettings.Mode) -> String {
        switch mode {
        case .off:
            return String(localized: "split-mode-off-detail", defaultValue: "All traffic goes through the VPN.")
        case .exclude:
            return String(localized: "split-mode-exclude-detail",
                          defaultValue: "Everything goes through the VPN except the addresses and sites you list.")
        case .include:
            return String(localized: "split-mode-include-detail",
                          defaultValue: "Only the addresses and sites you list go through the VPN. Everything else connects directly.")
        }
    }

    /// One line for the Settings screen, such as "Exclude listed · 3 entries".
    static func summary(_ settings: SplitTunnelSettings) -> String {
        guard settings.mode != .off else { return explanation(.off) }
        if settings.entries.count == 1 {
            return String(localized: "split-summary-one", defaultValue: "\(title(settings.mode)) · 1 entry")
        }
        return String(localized: "split-summary", defaultValue: "\(title(settings.mode)) · \(settings.entries.count) entries")
    }
}
