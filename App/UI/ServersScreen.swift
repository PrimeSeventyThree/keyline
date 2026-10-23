import SwiftUI

struct ServersScreenState {
    var servers: [ServerSummary] = []
    var activeServerID: String?
    var phase: ConnectScreenState.Phase = .disconnected
}

struct ServersScreen: View {
    let state: ServersScreenState
    var onAdd: () -> Void = {}
    var onConnect: (ServerSummary) -> Void = { _ in }
    var onShowMenu: (ServerSummary) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "servers-title", defaultValue: "Servers"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onAdd) {
                    Label(String(localized: "add-server", defaultValue: "Add server"), systemImage: "plus")
                }
                .buttonStyle(KeylineButtonStyle(kind: .primary))
                .keyboardShortcut("n", modifiers: .command)
            }
            if state.servers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(state.servers) { server in
                        ServerRow(server: server,
                                  status: server.id == state.activeServerID ? state.phase : .disconnected,
                                  onConnect: { onConnect(server) },
                                  onShowMenu: { onShowMenu(server) })
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "key")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Theme.accent)
            Text(String(localized: "servers-empty-title", defaultValue: "Add your first server"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(String(localized: "servers-empty-body",
                        defaultValue: "Paste the access key you were given. It starts with ss:// or ssconf://."))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: onAdd) { Text(String(localized: "add-server", defaultValue: "Add server")) }
                .buttonStyle(KeylineButtonStyle(kind: .primary))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ServerRow: View {
    let server: ServerSummary
    let status: ConnectScreenState.Phase
    let onConnect: () -> Void
    let onShowMenu: () -> Void

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 14) {
                FlagAvatar(country: server.country, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(server.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        if server.isDynamic {
                            Text(String(localized: "server-dynamic-badge", defaultValue: "Dynamic"))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundColor(Theme.upload)
                                .background(Capsule().fill(Theme.upload.opacity(0.14)))
                        }
                    }
                    Text(server.address.isEmpty ? server.placeName : "\(server.placeName) · \(server.address)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                statusView
                Button(action: onShowMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "server-options", defaultValue: "Server options")))
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .connected:
            Label(String(localized: "status-connected", defaultValue: "Connected"), systemImage: "circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accent)
                .imageScale(.small)
        case .connecting, .reconnecting, .disconnecting:
            Text(String(localized: "status-connecting", defaultValue: "Connecting…"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.warning)
        case .disconnected:
            Button(action: onConnect) { Text(String(localized: "connect", defaultValue: "Connect")) }
                .buttonStyle(KeylineButtonStyle())
        }
    }
}

/// The sheet for pasting an access key.
struct AddServerSheet: View {
    @Binding var accessKey: String
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering
    var errorMessage: String?
    var onCancel: () -> Void = {}
    var onAdd: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "add-server", defaultValue: "Add server"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(String(localized: "add-server-body",
                        defaultValue: "Paste the access key from your provider. Keys stay on this Mac, in your Keychain."))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            keyField
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(errorMessage == nil ? Theme.surfaceStroke : Theme.danger))
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundColor(Theme.danger)
            }
            HStack {
                Spacer()
                Button(String(localized: "cancel", defaultValue: "Cancel"), action: onCancel)
                    .buttonStyle(KeylineButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "add", defaultValue: "Add"), action: onAdd)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.background)
    }

    @ViewBuilder private var keyField: some View {
        if isSnapshotRendering {
            Text(accessKey.isEmpty ? "ss://… or ssconf://…" : accessKey)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("ss://… or ssconf://…", text: $accessKey)
                .textFieldStyle(.plain)
        }
    }
}
