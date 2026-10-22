import SwiftUI

/// Everything the Connect screen shows, as plain values.
struct ConnectScreenState {
    enum Phase: Equatable {
        case disconnected, connecting, connected, reconnecting, disconnecting
    }

    var phase: Phase = .disconnected
    /// The server the power button acts on.
    var server: ServerSummary?
    /// Recently used servers for quick switching, most recent first.
    var recentServers: [ServerSummary] = []
    var connectedSince: Date?
    var now = Date()
    /// Speeds in bytes per second, one sample per second, oldest first.
    var download: [Double] = []
    var upload: [Double] = []
    /// Round-trip times through the proxy in milliseconds, oldest first.
    var latency: [Double] = []
    var totals = TrafficStats()
    var errorMessage: String?

    var isActive: Bool { phase != .disconnected }
}

struct ConnectScreen: View {
    let state: ConnectScreenState
    var onToggleConnection: () -> Void = {}
    var onSelectServer: (ServerSummary) -> Void = { _ in }
    var onChangeServer: () -> Void = {}

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                RecentServersStrip(servers: state.recentServers, selectedID: state.server?.id, onSelect: onSelectServer)
                serverTitle.padding(.top, 14)
                timer.padding(.top, 26)
                PowerButton(phase: state.phase, action: onToggleConnection)
                    .padding(.top, 22)
                statusLine.padding(.top, 22)
                Button(action: onChangeServer) {
                    Label(String(localized: "change-server", defaultValue: "Change server"), systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(KeylineButtonStyle())
                .padding(.top, 14)
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity)

            StatsColumn(state: state)
                .frame(width: 270)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
    }

    private var serverTitle: some View {
        VStack(spacing: 4) {
            Text(state.server?.placeName ?? String(localized: "no-server", defaultValue: "No server"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            if let server = state.server {
                Text(server.address.isEmpty ? server.name : "\(server.name) · \(server.address)")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var timer: some View {
        VStack(spacing: 2) {
            Text(state.phase == .connected
                 ? String(localized: "connected-for", defaultValue: "Connected for")
                 : String(localized: "not-connected", defaultValue: "Not connected"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text(StatsFormat.duration(state.connectedSince.map { state.now.timeIntervalSince($0) } ?? 0))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(state.phase == .connected ? Theme.textPrimary : Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Text(String(localized: "status-label", defaultValue: "Status:"))
                .foregroundColor(Theme.textPrimary)
            Text(statusText).foregroundColor(statusColor)
        }
        .font(.system(size: 15, weight: .semibold))
    }

    private var statusText: String {
        if state.errorMessage != nil && state.phase == .disconnected {
            return String(localized: "status-failed", defaultValue: "Couldn’t connect")
        }
        switch state.phase {
        case .disconnected: return String(localized: "status-disconnected", defaultValue: "Disconnected")
        case .connecting: return String(localized: "status-connecting", defaultValue: "Connecting…")
        case .connected: return String(localized: "status-connected", defaultValue: "Connected")
        case .reconnecting: return String(localized: "status-reconnecting", defaultValue: "Reconnecting…")
        case .disconnecting: return String(localized: "status-disconnecting", defaultValue: "Disconnecting…")
        }
    }

    private var statusColor: Color {
        if state.errorMessage != nil && state.phase == .disconnected { return Theme.danger }
        switch state.phase {
        case .connected: return Theme.accent
        case .connecting, .reconnecting, .disconnecting: return Theme.warning
        case .disconnected: return Theme.textSecondary
        }
    }
}

/// The big round connect/disconnect button.
struct PowerButton: View {
    let phase: ConnectScreenState.Phase
    let action: () -> Void

    private var isOn: Bool { phase == .connected }
    private var isBusy: Bool { [.connecting, .reconnecting, .disconnecting].contains(phase) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isOn ? Theme.accent.opacity(0.10) : Color.white.opacity(0.03))
                    .frame(width: 196, height: 196)
                Circle()
                    .trim(from: 0, to: isBusy ? 0.72 : 1)
                    .stroke(isOn || isBusy ? Theme.accent : Color.white.opacity(0.14),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 176, height: 176)
                    .shadow(color: isOn ? Theme.accent.opacity(0.8) : .clear, radius: 16)
                Circle()
                    .fill(RadialGradient(
                        colors: isOn ? [Theme.accent.opacity(0.95), Theme.accentDeep] : [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                        center: .center, startRadius: 4, endRadius: 82))
                    .frame(width: 150, height: 150)
                Image(systemName: "power")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(isOn ? .white : Theme.textSecondary)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(phase == .disconnecting)
        .accessibilityLabel(Text(isOn || isBusy
            ? String(localized: "disconnect", defaultValue: "Disconnect")
            : String(localized: "connect", defaultValue: "Connect")))
        .keyboardShortcut("k", modifiers: .command)
    }
}

/// Up to five recent servers as flags; the selected one is larger.
struct RecentServersStrip: View {
    let servers: [ServerSummary]
    let selectedID: String?
    let onSelect: (ServerSummary) -> Void

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Self.arranged(servers.prefix(5), selectedID: selectedID)) { server in
                let isSelected = server.id == selectedID
                Button { onSelect(server) } label: {
                    FlagAvatar(country: server.country, size: isSelected ? 92 : 40, isSelected: isSelected)
                        .opacity(isSelected ? 1 : 0.75)
                }
                .buttonStyle(.plain)
                .help(server.name)
            }
        }
        .frame(height: 110)
    }

    /// The selected server in the middle, the others around it.
    static func arranged<S: Collection>(_ servers: S, selectedID: String?) -> [ServerSummary] where S.Element == ServerSummary {
        var others = servers.filter { $0.id != selectedID }
        guard let selected = servers.first(where: { $0.id == selectedID }) else { return Array(servers) }
        let middle = others.count / 2
        others.insert(selected, at: middle)
        return others
    }
}

/// Download, upload, latency and protection cards.
struct StatsColumn: View {
    let state: ConnectScreenState

    var body: some View {
        VStack(spacing: 12) {
            speedCard(title: String(localized: "stats-download", defaultValue: "Download"), icon: "arrow.down.circle",
                      samples: state.download, total: state.totals.bytesReceived, colors: [Theme.upload, Theme.accent])
            speedCard(title: String(localized: "stats-upload", defaultValue: "Upload"), icon: "arrow.up.circle",
                      samples: state.upload, total: state.totals.bytesSent, colors: [Theme.upload, Theme.accent])
            latencyCard
            ProtectionCard(isProtected: state.phase == .connected)
        }
    }

    private func speedCard(title: String, icon: String, samples: [Double], total: UInt64, colors: [Color]) -> some View {
        let isConnected = state.phase == .connected
        let speed = StatsFormat.speed(bytesPerSecond: samples.last ?? 0)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon).foregroundColor(Theme.textPrimary)
                    Spacer()
                    if isConnected {
                        Text(speed.value).foregroundColor(Theme.accent).monospacedDigit()
                            + Text(" \(speed.unit)").foregroundColor(Theme.textSecondary)
                    } else {
                        Text("–").foregroundColor(Theme.textTertiary)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                Sparkline(samples: isConnected ? samples : [], colors: colors)
                    .frame(height: 38)
                Text(isConnected
                     ? String(localized: "stats-session-total", defaultValue: "This session: \(StatsFormat.bytes(total))")
                     : String(localized: "stats-not-connected", defaultValue: "Shown while connected"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    private var latencyCard: some View {
        let current = state.phase == .connected ? state.latency.last : nil
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(String(localized: "stats-latency", defaultValue: "Latency"), systemImage: "waveform.path.ecg")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if let current {
                        Text(String(format: "%.0f", current)).foregroundColor(Theme.latency).monospacedDigit()
                            + Text(" ms").foregroundColor(Theme.textSecondary)
                    } else {
                        Text("–").foregroundColor(Theme.textTertiary)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                Sparkline(samples: state.phase == .connected ? state.latency : [], colors: [Theme.latency, Color.pink])
                    .frame(height: 38)
            }
        }
    }
}

struct ProtectionCard: View {
    let isProtected: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(String(localized: "protection-title", defaultValue: "Protection"),
                          systemImage: isProtected ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(isProtected
                         ? String(localized: "protection-on", defaultValue: "On")
                         : String(localized: "protection-off", defaultValue: "Off"))
                        .foregroundColor(isProtected ? Theme.accent : Theme.warning)
                }
                .font(.system(size: 13, weight: .medium))
                row(String(localized: "protection-traffic", defaultValue: "Traffic through your server"))
                row(String(localized: "protection-dns", defaultValue: "DNS through the tunnel"))
                row(String(localized: "protection-ipv6", defaultValue: "IPv6 blocked"))
            }
        }
    }

    private func row(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isProtected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isProtected ? Theme.accent : Theme.textTertiary)
            Text(text).foregroundColor(isProtected ? Theme.textSecondary : Theme.textTertiary)
        }
        .font(.system(size: 12))
    }
}

/// Puts a label's icon after its title, as in "Change server ›".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .bold))
        }
    }
}
