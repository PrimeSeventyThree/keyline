import NetworkExtension
import SwiftUI

/// Temporary test screen: install the extension, add servers, connect.
/// Replaced by the real UI in Phase 3.
struct ContentView: View {
    @ObservedObject var systemExtension: SystemExtensionManager
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var servers: ServerRepository
    @ObservedObject var connection: ConnectionModel

    @State private var accessKey = ""
    @State private var error: UserFacingError?

    var body: some View {
        Form {
            Section(header: Text("VPN component")) {
                HStack {
                    Text(extensionStateText)
                    Spacer()
                    if systemExtension.state == .needsApproval {
                        Button("Open System Settings") { systemExtension.openApprovalSettings() }
                    }
                    Button("Install") { systemExtension.activate() }
                    Button("Uninstall") { systemExtension.deactivate() }
                }
            }
            Section(header: Text("Add server")) {
                HStack {
                    TextField("ss://… or ssconf://…", text: $accessKey)
                    Button("Add") {
                        run { try await servers.add(accessKey: accessKey); accessKey = "" }
                    }
                    .disabled(accessKey.isEmpty)
                }
            }
            Section(header: Text("Servers")) {
                ForEach(servers.servers) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                            Text(server.address.isEmpty ? server.kind.rawValue : server.address)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(statusText(for: server)).foregroundColor(.secondary)
                        if connection.activeServerID == server.id {
                            Button("Disconnect") { Task { await connection.disconnect(serverID: server.id) } }
                        } else {
                            Button("Connect") { run { try await connection.connect(serverID: server.id) } }
                                .disabled(connection.busyServerID != nil)
                        }
                        Button("Forget") { Task { await connection.forget(serverID: server.id) } }
                    }
                }
            }
            if let error {
                Section(header: Text("Last error")) {
                    Text(error.message)
                    if let details = error.details {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        Task {
            do { try await action() } catch { self.error = UserFacingError(error) }
        }
    }

    private func statusText(for server: Server) -> String {
        guard tunnel.tunnelID == server.id else { return "" }
        switch tunnel.status {
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reconnecting"
        case .disconnecting: return "disconnecting"
        default: return ""
        }
    }

    private var extensionStateText: String {
        switch systemExtension.state {
        case .unknown: return "Not installed"
        case .activating: return "Installing…"
        case .needsApproval: return "Allow Keyline Tunnel in \(SystemExtensionManager.approvalLocation)"
        case .activated: return "Installed"
        case .notInApplications: return "Move Keyline to /Applications first"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
