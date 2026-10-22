import Foundation
import NetworkExtension

/// The parts of `TunnelController` that `ConnectionModel` drives; tests use a fake.
@MainActor
protocol TunnelControlling: AnyObject {
    var status: NEVPNStatus { get }
    /// The server ID the system VPN configuration belongs to.
    var tunnelID: String? { get }
    func start(id: String, name: String, transport: String) async throws
    func stop(id: String) async
}

/// Connects and disconnects servers: checks the VPN component is ready, resolves the
/// server's tunnel config (downloading dynamic configs), and starts the tunnel.
/// Every failure comes out as a `UserFacingError`.
@MainActor
final class ConnectionModel: ObservableObject {
    /// The server a connect or disconnect is in progress for.
    @Published private(set) var busyServerID: String?

    private let servers: ServerRepository
    private let tunnel: TunnelControlling
    private let isTunnelExtensionReady: () -> Bool

    init(servers: ServerRepository, tunnel: TunnelControlling, isTunnelExtensionReady: @escaping () -> Bool) {
        self.servers = servers
        self.tunnel = tunnel
        self.isTunnelExtensionReady = isTunnelExtensionReady
    }

    /// The server the VPN is connected (or connecting) to, if any.
    var activeServerID: String? {
        [.connected, .connecting, .reasserting].contains(tunnel.status) ? tunnel.tunnelID : nil
    }

    func connect(serverID: String) async throws {
        guard let server = servers.server(withID: serverID) else { return }
        busyServerID = serverID
        defer { busyServerID = nil }
        do {
            guard isTunnelExtensionReady() else { throw ServerError.tunnelExtensionNotReady }
            let config = try await servers.tunnelConfig(forServer: serverID)
            try await tunnel.start(id: server.id, name: server.name, transport: config.client)
        } catch {
            throw UserFacingError(error)
        }
    }

    func disconnect(serverID: String) async {
        busyServerID = serverID
        defer { busyServerID = nil }
        await tunnel.stop(id: serverID)
    }

    /// Forgets a server, disconnecting it first if it is active.
    func forget(serverID: String) async {
        if activeServerID == serverID {
            await disconnect(serverID: serverID)
        }
        servers.forget(id: serverID)
    }
}
