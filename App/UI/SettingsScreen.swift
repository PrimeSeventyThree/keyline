import SwiftUI

struct SettingsScreenState {
    var launchAtLogin = false
    var stopVPNOnQuit = false
    var language: AppSettings.Language = .system
    /// The language changed and takes effect after a restart.
    var languageNeedsRestart = false
    var extensionStatus = String(localized: "vpn-component-installed", defaultValue: "Installed and allowed")
    var extensionReady = true
    var version = "0.1.0 (2)"
    var splitTunnelSummary = String(localized: "split-mode-off-detail", defaultValue: "All traffic goes through the VPN.")
    /// Crash reports saved since the last report was sent or deleted.
    var crashReportCount = 0
}

struct SettingsScreen: View {
    @Binding var state: SettingsScreenState
    var onUninstallExtension: () -> Void = {}
    var onShowLicenses: () -> Void = {}
    var onRestart: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var onEditSplitTunnel: () -> Void = {}
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
                    section(String(localized: "settings-language", defaultValue: "Language")) {
                        SegmentedChoice(options: AppSettings.Language.allCases, selection: $state.language) {
                            switch $0 {
                            case .system: return String(localized: "language-system", defaultValue: "System language")
                            case .english: return "English"
                            case .russian: return "Русский"
                            }
                        }
                        if state.languageNeedsRestart {
                            HStack {
                                Text(String(localized: "language-restart", defaultValue: "Restart Keyline to switch the language."))
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                Button(String(localized: "restart", defaultValue: "Restart"), action: onRestart)
                                    .buttonStyle(KeylineButtonStyle(kind: .primary))
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
                                         detail: state.splitTunnelSummary)
                            Spacer()
                            Button(String(localized: "edit", defaultValue: "Edit…"), action: onEditSplitTunnel)
                                .buttonStyle(KeylineButtonStyle())
                        }
                    }
                    section(String(localized: "settings-about", defaultValue: "About")) {
                        HStack {
                            settingLabel("Keyline \(state.version)",
                                         detail: String(localized: "about-compatible",
                                                        defaultValue: "Works with Outline access keys. Not affiliated with the Outline Foundation."))
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Button(String(localized: "menu-check-updates", defaultValue: "Check for Updates…"),
                                   action: onCheckForUpdates)
                                .buttonStyle(KeylineButtonStyle())
                            Button(String(localized: "licenses", defaultValue: "Licenses"), action: onShowLicenses)
                                .buttonStyle(KeylineButtonStyle())
                            Button(String(localized: "send-report", defaultValue: "Send report…"), action: onSendReport)
                                .buttonStyle(KeylineButtonStyle())
                        }
                        if state.crashReportCount > 0 {
                            Label(String(localized: "crash-reports-saved",
                                         defaultValue: "Keyline quit unexpectedly. Crash details are saved for a report."),
                                  systemImage: "exclamationmark.bubble")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.warning)
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
