import Foundation
import Tun2socks

/// Calls into the Outline Go core through its `InvokeMethod` channel.
enum GoCore {
    /// A tunnel configuration parsed from an access key or a fetched dynamic config.
    /// Matches `firstHopAndTunnelConfigJSON` in client/go/outline/parse.go.
    struct TunnelConfig: Decodable {
        /// The client config the tunnel extension connects with.
        let client: String
        /// Address of the first server the traffic goes to, for display.
        let firstHop: String
        /// "tunneled", "partial" or "direct" (no proxy).
        let connectionType: String
    }

    /// Parses an `ss://` key, a legacy Shadowsocks JSON config or a YAML tunnel config.
    static func parseTunnelConfig(_ text: String) throws -> TunnelConfig {
        let value = try invoke(OutlineMethodParseTunnelConfig, text)
        return try JSONDecoder().decode(TunnelConfig.self, from: Data(value.utf8))
    }

    /// Downloads a dynamic access key's config over HTTPS.
    static func fetchResource(_ url: URL) throws -> String {
        try invoke(OutlineMethodFetchResource, url.absoluteString)
    }

    private static func invoke(_ method: String, _ input: String) throws -> String {
        guard let result = OutlineInvokeMethod(method, input) else {
            throw KeylineError.internalError(message: "\(method) returned no result")
        }
        if let error = result.error {
            throw KeylineError.platformError(error)
        }
        return result.value
    }
}
