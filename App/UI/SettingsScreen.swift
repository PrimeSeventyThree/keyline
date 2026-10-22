import SwiftUI

struct SettingsScreenState {
    enum Appearance: String, CaseIterable, Identifiable { case system, light, dark; var id: String { rawValue } }
    enum Language: String, CaseIterable, Identifiable { case system, english, russian; var id: String { rawValue } }

    var launchAtLogin = false
    var stopVPNOnQuit = false
    var appearance: Appearance = .system
    var language: Language = .system
    var extensionStatus = String(localized: "vpn-component-installed", defaultValue: "Installed and allowed")
    var extensionReady = true
    var version = "0.1.0 (2)"
}

struct SettingsScreen: View {
    @Binding var state: SettingsScreenState
    var onUninstallExtension: () -> Void = {}
    var onShowLicenses: () -> Void = {}
    var onSendReport: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings-title", defaultValue: "Settings"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    section(String(localized: "settings-general", defaultValue: "General")) {
                        Toggle(isOn: $state.launchAtLogin) {
                            settingLabel(String(localized: "settings-launch-at-login", defaultValue: "Open Keyline at login"))
                        }
                        Toggle(isOn: $state.stopVPNOnQuit) {
                            settingLabel(String(localized: "settings-stop-on-quit", defaultValue: "Disconnect when quitting Keyline"),
                                         detail: String(localized: "settings-stop-on-quit-detail",
                                                        defaultValue: "When off, the VPN stays on after you quit."))
                        }
                    }
                    section(String(localized: "settings-appearance", defaultValue: "Appearance")) {
                        settingLabel(String(localized: "settings-theme", defaultValue: "Theme"))
                        SegmentedChoice(options: SettingsScreenState.Appearance.allCases, selection: $state.appearance) {
                            switch $0 {
                            case .system: return String(localized: "appearance-system", defaultValue: "System")
                            case .light: return String(localized: "appearance-light", defaultValue: "Light")
                            case .dark: return String(localized: "appearance-dark", defaultValue: "Dark")
                            }
                        }
                        settingLabel(String(localized: "settings-language", defaultValue: "Language"))
                        SegmentedChoice(options: SettingsScreenState.Language.allCases, selection: $state.language) {
                            switch $0 {
                            case .system: return String(localized: "language-system", defaultValue: "System language")
                            case .english: return "English"
                            case .russian: return "Русский"
                            }
                        }
                    }
                }
                VStack(spacing: 16) {
                    section(String(localized: "settings-vpn", defaultValue: "VPN")) {
                        HStack {
                            settingLabel(String(localized: "vpn-component", defaultValue: "VPN component"),
                                         detail: state.extensionStatus)
                            Spacer()
                            Button(String(localized: "uninstall", defaultValue: "Uninstall"), action: onUninstallExtension)
                                .buttonStyle(KeylineButtonStyle(kind: .destructive))
                        }
                        HStack {
                            settingLabel(String(localized: "split-tunneling", defaultValue: "Split tunneling"),
                                         detail: String(localized: "split-tunneling-soon",
                                                        defaultValue: "Choose which sites skip or use the VPN. Coming soon."))
                            Spacer()
                        }
                        .opacity(0.6)
                    }
                    section(String(localized: "settings-about", defaultValue: "About")) {
                        HStack {
                            settingLabel("Keyline \(state.version)",
                                         detail: String(localized: "about-compatible",
                                                        defaultValue: "Works with Outline access keys. Not affiliated with the Outline Foundation."))
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Button(String(localized: "licenses", defaultValue: "Licenses"), action: onShowLicenses)
                                .buttonStyle(KeylineButtonStyle())
                            Button(String(localized: "send-report", defaultValue: "Send report…"), action: onSendReport)
                                .buttonStyle(KeylineButtonStyle())
                        }
                        Text("IP geolocation by DB-IP (db-ip.com)")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .toggleStyle(KeylineToggleStyle())
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Card { VStack(alignment: .leading, spacing: 14) { content() } }
        }
    }

    private func settingLabel(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textPrimary)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A segmented control drawn in SwiftUI to match the theme.
struct SegmentedChoice<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(option == selection ? Color.black.opacity(0.85) : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(option == selection ? Theme.accent : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.22)))
    }
}
