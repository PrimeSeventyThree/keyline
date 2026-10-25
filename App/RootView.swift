import NetworkExtension
import SwiftUI

/// The main window: turns the app's models into screen state and screen actions into
/// model calls.
struct RootView: View {
    @ObservedObject var systemExtension: SystemExtensionManager
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var servers: ServerRepository
    @ObservedObject var connection: ConnectionModel
    @ObservedObject var stats: StatsSampler
    @ObservedObject var selection: ServerSelection
    @ObservedObject var settings: AppSettings
    @ObservedObject var crashReports: CrashReportStore
    let updater: Updater

    @State private var section: MainSection = .connect
    @State private var launchAtLogin = LoginItem().isEnabled
    @State private var showingLicenses = false
    @State private var showingAutoConnectExplainer = false
    @State private var showingSplitTunnel = false
    @State private var showingReport = false
    @State private var reportDescription = ""
    @State private var reportIncludesCrashes = true

    @State private var isAddingServer = false
    @State private var newAccessKey = ""
    @State private var addServerError: String?
    @State private var addServerNote: String?
    @State private var clipboard = ClipboardWatcher()

    @State private var renamingServer: ServerSummary?
    @State private var newName = ""

    @State private var forgottenServer: ServerSummary?
    @State private var shownError: UserFacingError?
    /// The last connect failure, shown in the status line until the next attempt.
    @State private var lastConnectError: UserFacingError?

    @State private var onboardingStep: OnboardingScreen.Step = .welcome

    var body: some View {
        if settings.hasCompletedOnboarding {
            mainWindow
        } else {
            onboarding
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        OnboardingScreen(
            step: onboardingStep,
            extensionState: systemExtension.state,
            accessKey: $newAccessKey,
            addServerError: addServerError,
            onContinue: {
                if let next = OnboardingScreen.Step(rawValue: onboardingStep.rawValue + 1) { onboardingStep = next }
            },
            onBack: {
                if let previous = OnboardingScreen.Step(rawValue: onboardingStep.rawValue - 1) { onboardingStep = previous }
            },
            onInstall: { systemExtension.activate() },
            onOpenSettings: { systemExtension.openApprovalSettings() },
            onAddServer: {
                Task {
                    do {
                        let server = try await servers.add(accessKey: newAccessKey)
                        selection.select(server.id)
                        finishOnboarding()
                    } catch {
                        addServerError = UserFacingError(error).message
                    }
                }
            },
            onSkip: finishOnboarding)
        .frame(minWidth: 1120, minHeight: 720)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            // A link during setup fills in the first server.
            guard let key = AccessKeyDetection.candidate(in: url.absoluteString) else { return }
            newAccessKey = key
            onboardingStep = .addServer
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private func finishOnboarding() {
        newAccessKey = ""
        addServerError = nil
        section = .connect
        settings.hasCompletedOnboarding = true
    }

    // MARK: - Main window

    private var mainWindow: some View {
        MainWindow(section: $section, isConnected: tunnel.status == .connected) {
            switch section {
            case .connect:
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    ConnectScreen(state: connectState(now: context.date),
                                  onToggleConnection: toggleConnection,
                                  onSelectServer: { select($0.id) },
                                  onChangeServer: { section = .servers },
                                  onSetupAction: setupAction)
                }
            case .servers:
                ServersScreen(state: serversState,
                              onAdd: { showAddServer() },
                              onConnect: { connect($0.id) },
                              actions: ServerActions(
                                rename: { server in newName = server.name; renamingServer = server },
                                setCountry: { server, code in servers.setCountryOverride(id: server.id, countryCode: code) },
                                forget: forget))
            case .settings:
                SettingsScreen(state: settingsBinding,
                               onUninstallExtension: { systemExtension.deactivate() },
                               onShowLicenses: { showingLicenses = true },
                               onRestart: relaunch,
                               onCheckForUpdates: { updater.checkForUpdates() },
                               onEditSplitTunnel: { showingSplitTunnel = true },
                               onSendReport: { showingReport = true })
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .overlay(alignment: .bottom) { undoToast }
        .sheet(isPresented: $isAddingServer) {
            AddServerSheet(accessKey: $newAccessKey, errorMessage: addServerError, note: addServerNote,
                           onCancel: { isAddingServer = false }, onAdd: addServer)
        }
        .sheet(isPresented: $showingLicenses) { LicensesSheet(onDone: { showingLicenses = false }) }
        .sheet(isPresented: $showingSplitTunnel) {
            SplitTunnelSheet(settings: splitTunnelBinding, onDone: { showingSplitTunnel = false })
        }
        .sheet(isPresented: $showingReport) {
            ReportSheet(description: $reportDescription, includeCrashReports: $reportIncludesCrashes,
                        crashReportCount: crashReports.reports.count,
                        onCancel: { showingReport = false },
                        onOpenIssue: openReport,
                        onDeleteCrashReports: { crashReports.deleteAll() })
        }
        .sheet(item: $renamingServer) { server in
            RenameServerSheet(name: $newName,
                              onCancel: { renamingServer = nil },
                              onSave: { servers.rename(id: server.id, to: newName); renamingServer = nil })
        }
        // Shown once, after the first connection, as upstream does.
        .alert(String(localized: "auto-connect-title", defaultValue: "Keyline reconnects automatically"),
               isPresented: $showingAutoConnectExplainer) {
            Button(String(localized: "auto-connect-ok", defaultValue: "Got it")) {
                settings.hasSeenAutoConnectExplainer = true
            }
        } message: {
            Text(String(localized: "auto-connect-body",
                        defaultValue: "While you’re connected, Keyline turns the VPN back on after your Mac restarts or switches networks, even if Keyline isn’t open. To stop it, disconnect in Keyline."))
        }
        .alert(shownError?.message ?? "", isPresented: Binding(get: { shownError != nil }, set: { if !$0 { shownError = nil } }),
               presenting: shownError) { error in
            if let details = error.details {
                Button(String(localized: "copy-details", defaultValue: "Copy details")) { copyToPasteboard(details) }
            }
            Button(String(localized: "ok", defaultValue: "OK"), role: .cancel) {}
        } message: { error in
            if let details = error.details { Text(details).font(.caption) }
        }
        .onReceive(tunnel.$status.removeDuplicates()) { status in
            if status == .connected {
                stats.start(source: tunnel)
                if let id = tunnel.tunnelID { selection.recordConnection(to: id) }
                if !settings.hasSeenAutoConnectExplainer { showingAutoConnectExplainer = true }
            } else if status == .disconnected || status == .invalid {
                stats.stop()
            }
        }
        .onAppear {
            if tunnel.status == .connected { stats.start(source: tunnel) }
        }
        .onOpenURL(perform: handle)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboard()
        }
        // Links go to this window instead of opening another one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    // MARK: - Screen state

    /// The server the VPN is on, else the selected one.
    private var shownServer: Server? {
        if let activeID = connection.activeServerID, let active = servers.server(withID: activeID) { return active }
        return selection.resolvedServer(in: servers.servers)
    }

    private var phase: ConnectScreenState.Phase {
        if connection.busyServerID != nil, tunnel.status == .disconnected || tunnel.status == .invalid {
            return .connecting // Fetching a dynamic config, before the tunnel starts.
        }
        switch tunnel.status {
        case .connecting: return .connecting
        case .connected: return .connected
        case .reasserting: return .reconnecting
        case .disconnecting: return .disconnecting
        default: return .disconnected
        }
    }

    private func connectState(now: Date) -> ConnectScreenState {
        ConnectScreenState(
            phase: phase,
            server: shownServer.map(ServerSummary.init),
            recentServers: selection.recentServers(in: servers.servers).map(ServerSummary.init),
            connectedSince: phase == .connected ? tunnel.connectedDate : nil,
            now: now,
            download: stats.download, upload: stats.upload, latency: stats.latency, totals: stats.totals,
            errorMessage: lastConnectError?.message,
            setupNotice: setupNotice)
    }

    private var serversState: ServersScreenState {
        ServersScreenState(servers: servers.servers.map(ServerSummary.init),
                           activeServerID: connection.activeServerID ?? connection.busyServerID,
                           phase: phase)
    }

    /// Split tunneling as the sheet edits it; every change is saved and applied right away.
    private var splitTunnelBinding: Binding<SplitTunnelSettings> {
        Binding(
            get: { settings.splitTunnel },
            set: { new in
                guard new != settings.splitTunnel else { return }
                settings.splitTunnel = new
                Task { await tunnel.applySplitTunnel(new) }
            })
    }

    /// Settings as the screen shows them; changes go straight to the models.
    private var settingsBinding: Binding<SettingsScreenState> {
        Binding(
            get: {
                SettingsScreenState(
                    launchAtLogin: launchAtLogin,
                    stopVPNOnQuit: settings.stopVPNOnQuit,
                    language: settings.language,
                    languageNeedsRestart: settings.needsRestartForLanguage,
                    extensionStatus: extensionStatusText,
                    extensionReady: systemExtension.state == .activated,
                    version: Self.versionText,
                    splitTunnelSummary: SplitTunnelSheet.summary(settings.splitTunnel),
                    crashReportCount: crashReports.reports.count)
            },
            set: { new in
                if new.launchAtLogin != launchAtLogin { setLaunchAtLogin(new.launchAtLogin) }
                settings.stopVPNOnQuit = new.stopVPNOnQuit
                if new.language != settings.language { settings.language = new.language }
            })
    }

    private var extensionStatusText: String {
        switch systemExtension.state {
        case .activated: return String(localized: "vpn-component-installed", defaultValue: "Installed and allowed")
        case .activating, .unknown: return String(localized: "vpn-component-checking", defaultValue: "Checking…")
        case .needsApproval: return String(localized: "vpn-component-needs-approval", defaultValue: "Waiting for your approval in System Settings")
        case .notInApplications: return String(localized: "vpn-component-move-app", defaultValue: "Move Keyline to Applications to install it")
        case .failed(let reason): return reason
        }
    }

    /// Opens the pre-filled GitHub issue in the browser, where the user reviews it.
    private func openReport() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let url = CrashReportStore.issueURL(
            description: reportDescription,
            reports: reportIncludesCrashes ? crashReports.reports : [],
            appVersion: Self.versionText,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        NSWorkspace.shared.open(url)
        showingReport = false
        reportDescription = ""
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem().setEnabled(enabled)
        } catch {
            shownError = UserFacingError(
                message: String(localized: "launch-at-login-failed", defaultValue: "Keyline couldn’t change whether it opens at login."),
                details: String(describing: error))
        }
        launchAtLogin = LoginItem().isEnabled
    }

    /// Opens a new copy of Keyline and quits this one, to apply a language change.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                AppDelegate.isRelaunching = true
                NSApp.terminate(nil)
            }
        }
    }

    private var setupNotice: SetupNotice? {
        switch systemExtension.state {
        case .activated, .unknown, .activating:
            return servers.servers.isEmpty
                ? SetupNotice(message: String(localized: "setup-add-server", defaultValue: "Add a server to get started."),
                              actionTitle: String(localized: "add-server", defaultValue: "Add server"))
                : nil
        case .needsApproval:
            return SetupNotice(
                message: String(localized: "setup-approve",
                                defaultValue: "Allow Keyline Tunnel in \(SystemExtensionManager.approvalLocation)."),
                actionTitle: String(localized: "open-system-settings", defaultValue: "Open System Settings"))
        case .notInApplications:
            return SetupNotice(message: String(localized: "setup-move-to-applications",
                                               defaultValue: "Move Keyline to the Applications folder, then open it again."),
                               actionTitle: nil)
        case .failed(let reason):
            return SetupNotice(message: String(localized: "setup-failed", defaultValue: "The VPN component couldn’t be installed: \(reason)"),
                               actionTitle: String(localized: "try-again", defaultValue: "Try again"))
        }
    }

    // MARK: - Actions

    private func setupAction() {
        switch systemExtension.state {
        case .needsApproval: systemExtension.openApprovalSettings()
        case .failed: systemExtension.activate()
        default: showAddServer()
        }
    }

    private func toggleConnection() {
        if let active = connection.activeServerID {
            Task { await connection.disconnect(serverID: active) }
        } else if let server = shownServer {
            connect(server.id)
        } else {
            showAddServer()
        }
    }

    /// Selecting another server while connected switches the VPN to it.
    private func select(_ id: String) {
        selection.select(id)
        if connection.activeServerID != nil, connection.activeServerID != id {
            connect(id)
        }
    }

    private func connect(_ id: String) {
        selection.select(id)
        lastConnectError = nil
        Task {
            do {
                try await connection.connect(serverID: id)
            } catch {
                let shown = UserFacingError(error)
                lastConnectError = shown
                shownError = shown
            }
        }
    }

    /// Opens the Add server sheet, pre-filled with `accessKey` or a key on the clipboard.
    private func showAddServer(accessKey: String? = nil, note: String? = nil) {
        newAccessKey = accessKey ?? AccessKeyDetection.candidate(in: NSPasteboard.general.string(forType: .string)) ?? ""
        addServerNote = note
        addServerError = nil
        isAddingServer = true
    }

    /// Offers an access key copied since Keyline was last in front, as upstream does.
    private func checkClipboard() {
        guard !isAddingServer else { return }
        let pasteboard = NSPasteboard.general
        guard let key = clipboard.newAccessKey(changeCount: pasteboard.changeCount,
                                               text: pasteboard.string(forType: .string),
                                               isAlreadyAdded: { servers.server(withAccessKey: $0) != nil })
        else { return }
        section = .servers
        showAddServer(accessKey: key,
                      note: String(localized: "add-server-from-clipboard", defaultValue: "Found an access key on your clipboard."))
    }

    /// keyline://show links show a section. ss:// and ssconf:// links open the Add server
    /// sheet, or select the server if it's already added.
    private func handle(_ url: URL) {
        if let shown = MainSection(showURL: url) {
            section = shown
            return
        }
        guard let key = AccessKeyDetection.candidate(in: url.absoluteString) else { return }
        if let existing = servers.server(withAccessKey: key) {
            selection.select(existing.id)
            section = .connect
            return
        }
        section = .servers
        showAddServer(accessKey: key, note: String(localized: "add-server-from-link", defaultValue: "Opened from a link."))
    }

    private func addServer() {
        Task {
            do {
                let server = try await servers.add(accessKey: newAccessKey)
                if servers.servers.count == 1 { selection.select(server.id) }
                isAddingServer = false
            } catch {
                addServerError = UserFacingError(error).message
            }
        }
    }

    private func forget(_ server: ServerSummary) {
        Task {
            await connection.forget(serverID: server.id)
            forgottenServer = server
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if forgottenServer?.id == server.id { forgottenServer = nil }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if let server = forgottenServer {
            HStack(spacing: 14) {
                Text(String(localized: "server-forgotten", defaultValue: "“\(server.name)” forgotten."))
                    .foregroundColor(Theme.textPrimary)
                Button(String(localized: "undo", defaultValue: "Undo")) {
                    servers.undoForget(id: server.id)
                    forgottenServer = nil
                }
                .buttonStyle(KeylineButtonStyle(kind: .primary))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.08, green: 0.18, blue: 0.15)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.surfaceStroke))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
