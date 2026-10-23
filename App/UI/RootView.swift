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

    @State private var section: MainSection = .connect
    @State private var settings = SettingsScreenState()

    @State private var isAddingServer = false
    @State private var newAccessKey = ""
    @State private var addServerError: String?

    @State private var renamingServer: ServerSummary?
    @State private var newName = ""

    @State private var forgottenServer: ServerSummary?
    @State private var shownError: UserFacingError?
    /// The last connect failure, shown in the status line until the next attempt.
    @State private var lastConnectError: UserFacingError?

    var body: some View {
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
                              onAdd: showAddServer,
                              onConnect: { connect($0.id) },
                              actions: ServerActions(
                                rename: { server in newName = server.name; renamingServer = server },
                                setCountry: { server, code in servers.setCountryOverride(id: server.id, countryCode: code) },
                                forget: forget))
            case .settings:
                SettingsScreen(state: $settings,
                               onUninstallExtension: { systemExtension.deactivate() })
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .overlay(alignment: .bottom) { undoToast }
        .sheet(isPresented: $isAddingServer) {
            AddServerSheet(accessKey: $newAccessKey, errorMessage: addServerError,
                           onCancel: { isAddingServer = false }, onAdd: addServer)
        }
        .sheet(item: $renamingServer) { server in
            RenameServerSheet(name: $newName,
                              onCancel: { renamingServer = nil },
                              onSave: { servers.rename(id: server.id, to: newName); renamingServer = nil })
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
            } else if status == .disconnected || status == .invalid {
                stats.stop()
            }
        }
        .onAppear {
            if tunnel.status == .connected { stats.start(source: tunnel) }
        }
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

    private func showAddServer() {
        newAccessKey = (NSPasteboard.general.string(forType: .string)).flatMap { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("ss://") || trimmed.hasPrefix("ssconf://") ? trimmed : nil
        } ?? ""
        addServerError = nil
        isAddingServer = true
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
