import Foundation
import Tun2socks

/// A tunnel configuration parsed from an access key or a fetched dynamic config.
/// Matches `firstHopAndTunnelConfigJSON` in client/go/outline/parse.go.
struct TunnelConfig: Decodable, Equatable {
    /// The client config the tunnel extension connects with.
    let client: String
    /// Address of the first server the traffic goes to, for display. Empty when the
    /// stream and packet paths start at different servers.
    let firstHop: String
    let connectionType: ConnectionType

    /// How the config reaches the internet. Matches `ConnType` in
    /// client/go/outline/configregistry/types.go.
    enum ConnectionType: String, Decodable {
        case tunneled, partial, direct, blocked
    }
}

/// The parts of the Go core the app uses. Tests substitute a fake for network access.
protocol TunnelConfigService: Sendable {
    /// Parses an `ss://` key, a legacy Shadowsocks JSON config or a YAML tunnel config.
    func parseTunnelConfig(_ text: String) throws -> TunnelConfig
    /// Downloads a dynamic access key's config over HTTPS.
    func fetchResource(_ url: URL) throws -> String
    /// Deletes per-server data the Go core keeps, such as session reporter cookies.
    func eraseServiceStorage(serverID: String) throws
}

/// Calls into the Outline Go core through its `InvokeMethod` channel. All calls block,
/// and `fetchResource` goes over the network, so call them off the main thread.
struct GoCore: TunnelConfigService {
    func parseTunnelConfig(_ text: String) throws -> TunnelConfig {
        let value = try invoke(OutlineMethodParseTunnelConfig, text)
        return try JSONDecoder().decode(TunnelConfig.self, from: Data(value.utf8))
    }

    func fetchResource(_ url: URL) throws -> String {
        try invoke(OutlineMethodFetchResource, url.absoluteString)
    }

    func eraseServiceStorage(serverID: String) throws {
        _ = try invoke(OutlineMethodEraseServiceStorage, serverID)
    }

    private func invoke(_ method: String, _ input: String) throws -> String {
        guard let result = OutlineInvokeMethod(method, input) else {
            throw KeylineError.internalError(message: "\(method) returned no result")
        }
        if let error = result.error {
            throw KeylineError.platformError(error)
        }
        return result.value
    }
}
