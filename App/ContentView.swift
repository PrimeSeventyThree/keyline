import NetworkExtension
import SwiftUI

/// Phase 1 test screen: install the extension, then connect with a pasted access key.
/// Replaced by the real UI in Phase 3.
struct ContentView: View {
    @StateObject private var systemExtension = SystemExtensionManager()
    @StateObject private var tunnel = TunnelController()
    @State private var accessKey = ""
    @State private var isBusy = false
    @State private var errorText: String?

    private static let tunnelID = "phase1-test"

    var body: some View {
        Form {
            Section(header: Text("VPN component")) {
                HStack {
                    Text(extensionStateText)
                    Spacer()
                    Button("Install") { systemExtension.activate() }
                    Button("Uninstall") { systemExtension.deactivate() }
                }
            }
            Section(header: Text("Access key")) {
                TextField("ss://… or ssconf://…", text: $accessKey)
                HStack {
                    Text("Status: \(statusText)")
                    Spacer()
                    Button("Connect", action: connect)
                        .disabled(isBusy || accessKey.isEmpty)
                    Button("Disconnect") { Task { await tunnel.stop(id: Self.tunnelID) } }
                        .disabled(isBusy)
                }
            }
            if let errorText {
                Section(header: Text("Last error")) {
                    Text(errorText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
        .onAppear { systemExtension.activate() }
    }

    private func connect() {
        let key = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isBusy = true
        errorText = nil
        Task {
            defer { isBusy = false }
            do {
                // Go calls block, and fetching a dynamic key goes over the network.
                let config = try await Task.detached { try Self.tunnelConfig(forAccessKey: key) }.value
                guard config.connectionType != "direct" else {
                    throw KeylineError.invalidConfig(message: "proxyless configs are not supported")
                }
                try await tunnel.start(id: Self.tunnelID, name: "Keyline (\(config.firstHop))", transport: config.client)
            } catch {
                let error = KeylineError(error)
                errorText = "\(error.code)\n\(error.json)"
            }
        }
    }

    /// Static keys are parsed directly. Dynamic keys (ssconf:// or https://) point to a
    /// config that is downloaded first. The #fragment holds the server name, not config.
    private nonisolated static func tunnelConfig(forAccessKey key: String) throws -> GoCore.TunnelConfig {
        let keyWithoutName = String(key.prefix { $0 != "#" })
        let lowercased = keyWithoutName.lowercased()
        guard lowercased.hasPrefix("ssconf://") || lowercased.hasPrefix("https://") else {
            return try GoCore.parseTunnelConfig(keyWithoutName)
        }
        let httpsKey = "https://" + keyWithoutName.drop { $0 != ":" }.dropFirst(3)
        guard let url = URL(string: httpsKey) else {
            throw KeylineError.invalidConfig(message: "not a valid URL")
        }
        return try GoCore.parseTunnelConfig(GoCore.fetchResource(url))
    }

    private var extensionStateText: String {
        switch systemExtension.state {
        case .unknown: return "Not installed"
        case .activating: return "Installing…"
        case .needsApproval: return "Allow Keyline in System Settings › Privacy & Security"
        case .activated: return "Installed"
        case .notInApplications: return "Move Keyline to /Applications first"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var statusText: String {
        switch tunnel.status {
        case .invalid: return "not configured"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reconnecting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }
}
