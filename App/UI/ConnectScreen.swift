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
    /// Shown above everything when the VPN component needs installing or approving.
    var setupNotice: SetupNotice?

    var isActive: Bool { phase != .disconnected }
}

struct ConnectScreen: View {
    let state: ConnectScreenState
    var onToggleConnection: () -> Void = {}
    var onSelectServer: (ServerSummary) -> Void = { _ in }
    var onChangeServer: () -> Void = {}
    var onSetupAction: () -> Void = {}

    /// Each side's pair of cards at the minimum window size; both sides line up.
    static let minimumWingSize = CGSize(width: 250, height: 280)
    /// The screen's size at the minimum window size (1120 × 720 less the sidebar).
    static let minimumScreenSize = CGSize(width: 1020, height: 720)
    /// How much the cards grow in a large window: 250 to 340 pt wide.
    static let maximumWingScale: CGFloat = 1.36
    /// Beyond this width the layout stops spreading and stays centred.
    static let maximumLayoutWidth: CGFloat = 1400

    /// The cards grow with the screen, keeping their proportions, from the minimum size up to
    /// `maximumWingScale` (#24).
    static func wingSize(forScreen size: CGSize) -> CGSize {
        let scale = min(size.width / minimumScreenSize.width, size.height / minimumScreenSize.height)
        let clamped = min(max(scale, 1), maximumWingScale)
        return CGSize(width: (minimumWingSize.width * clamped).rounded(), height: (minimumWingSize.height * clamped).rounded())
    }

    private var cards: StatsCards { StatsCards(state: state) }

    /// Traffic cards on the left, connection cards on the right, the main column centred
    /// between them.
    var body: some View {
        GeometryReader { geometry in
            let wing = Self.wingSize(forScreen: geometry.size)
            HStack(spacing: 24) {
                VStack(spacing: 12) { cards.download; cards.upload }
                    .frame(width: wing.width, height: wing.height)
                mainColumn
                    .frame(maxWidth: .infinity)
                VStack(spacing: 12) { cards.latency; cards.protection }
                    .frame(width: wing.width, height: wing.height)
            }
            .frame(maxWidth: Self.maximumLayoutWidth)
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            WorldMapView()
                .padding(.horizontal, 20)
                .padding(.vertical, 60))
        .overlay(alignment: .top) {
            // Over the layout rather than in it, so the main column never moves.
            if let notice = state.setupNotice {
                SetupBanner(notice: notice, action: onSetupAction).padding(.top, 12)
            }
        }
    }

    /// Flags, country, timer, power button and status, centred on one axis.
    private var mainColumn: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            RecentServersStrip(servers: state.recentServers, selectedID: state.server?.id, onSelect: onSelectServer)
            serverTitle.padding(.top, 14)
            timer.padding(.top, 26)
            PowerButton(phase: state.phase, action: onToggleConnection)
                .padding(.top, 22)
            statusLine.padding(.top, 22)
            changeServerButton.padding(.top, 14)
            Spacer(minLength: 8)
        }
    }

    private var changeServerButton: some View {
        Button(action: onChangeServer) {
            Label(String(localized: "change-server", defaultValue: "Change server"), systemImage: "chevron.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(KeylineButtonStyle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Bool { phase == .connected }
    private var isBusy: Bool { [.connecting, .reconnecting, .disconnecting].contains(phase) }
    /// While busy the ring spins; while connected the glow breathes. Reduce Motion stops both.
    private var animates: Bool { (isBusy || isOn) && !reduceMotion }

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { context in
                let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
                let spin = isBusy ? (time.truncatingRemainder(dividingBy: 1.2) / 1.2) * 360 : 0
                let breath = isOn ? 0.5 + 0.5 * sin(time * 2 * .pi / 3) : 0 // 0…1 every 3 s
                ZStack {
                    Circle()
                        .fill(isOn ? Theme.accent.opacity(0.08 + 0.06 * breath) : Color.white.opacity(0.03))
                        .frame(width: 196, height: 196)
                    Circle()
                        .trim(from: 0, to: isBusy ? 0.72 : 1)
                        .stroke(isOn || isBusy ? Theme.accent : Color.white.opacity(0.14),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90 + spin))
                        .frame(width: 176, height: 176)
                        .shadow(color: isOn ? Theme.accent.opacity(0.6 + 0.3 * breath) : .clear, radius: 12 + 8 * breath)
                    Circle()
                        .fill(RadialGradient(
                            colors: isOn ? [Theme.accent.opacity(0.95), Theme.accentDeep] : [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                            center: .center, startRadius: 4, endRadius: 82))
                        .frame(width: 150, height: 150)
                    Image(systemName: "power")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(isOn ? .white : Theme.textSecondary)
                }
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

/// The download, upload, latency and protection cards, placed in the two side columns.
struct StatsCards {
    let state: ConnectScreenState

    var download: some View {
        speedCard(title: String(localized: "stats-download", defaultValue: "Download"), icon: "arrow.down.circle",
                  samples: state.download, total: state.totals.bytesReceived, colors: [Theme.upload, Theme.accent])
    }

    var upload: some View {
        speedCard(title: String(localized: "stats-upload", defaultValue: "Upload"), icon: "arrow.up.circle",
                  samples: state.upload, total: state.totals.bytesSent, colors: [Theme.upload, Theme.accent])
    }

    var protection: some View {
        ProtectionCard(isProtected: state.phase == .connected)
    }

    private func speedCard(title: String, icon: String, samples: [Double], total: UInt64, colors: [Color]) -> some View {
        let isConnected = state.phase == .connected
        let speed = StatsFormat.speed(bytesPerSecond: samples.last ?? 0)
        return Card(fillsHeight: true) {
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
                    .frame(minHeight: 30, maxHeight: .infinity)
                Text(isConnected
                     ? String(localized: "stats-session-total", defaultValue: "This session: \(StatsFormat.bytes(total))")
                     : String(localized: "stats-not-connected", defaultValue: "Shown while connected"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    var latency: some View {
        let current = state.phase == .connected ? state.latency.last : nil
        return Card(fillsHeight: true) {
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
                    .frame(minHeight: 30, maxHeight: .infinity)
                Text(state.phase == .connected && !state.latency.isEmpty
                     ? String(localized: "stats-latency-average",
                              defaultValue: "Average: \(String(format: "%.0f", state.latency.reduce(0, +) / Double(state.latency.count))) ms")
                     : String(localized: "stats-not-connected", defaultValue: "Shown while connected"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }
}

struct ProtectionCard: View {
    let isProtected: Bool

    var body: some View {
        Card(fillsHeight: true) {
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

/// Why the VPN can't connect yet, and what the user can do about it.
struct SetupNotice: Equatable {
    var message: String
    var actionTitle: String?
}

struct SetupBanner: View {
    let notice: SetupNotice
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.warning)
            Text(notice.message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let title = notice.actionTitle {
                Button(title, action: action)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.warning.opacity(0.35)))
        .frame(maxWidth: 680)
    }
}
