import Foundation
import os

/// Keys of `NETunnelProviderProtocol.providerConfiguration`, written by the app and read
/// by the tunnel extension. Same keys as upstream's OutlineVpn.swift.
enum TunnelConfigKey {
    static let tunnelID = "id"
    static let transport = "transport"
}

/// Messages the app sends to the extension with `NETunnelProviderSession.sendProviderMessage`.
enum TunnelAppMessage {
    /// Returns the last disconnect error as a property-list-encoded `LastTunnelError`.
    /// Needed on macOS 12, where `fetchLastDisconnectError` is unavailable.
    static let fetchLastError = "fetchLastDisconnectDetailedJsonError"
}

/// The last error that stopped the tunnel, persisted by the extension because the system
/// unloads it after a failed start.
struct LastTunnelError: Codable {
    let errorCode: String
    let errorJson: String
}

extension Logger {
    static func keyline(_ category: String) -> Logger {
        Logger(subsystem: KeylineIdentifiers.app, category: category)
    }
}
