import Foundation

/// Errors from managing servers and preparing a connection, before the tunnel extension
/// is involved. Tunnel and Go core errors are `KeylineError`s.
enum ServerError: Error {
    /// The text is not an `ss://`, `ssconf://` or `https://` access key, or the Go core
    /// rejected it.
    case invalidAccessKey(cause: Error?)
    case alreadyAdded(serverName: String)
    /// The server's access key is missing from the Keychain.
    case missingAccessKey
    /// A dynamic key returned an empty config.
    case emptyDynamicConfig
    /// The config sends traffic directly instead of through a proxy, which a VPN can't use.
    case proxylessNotSupported
    /// The VPN component (system extension) is not installed and approved yet.
    case tunnelExtensionNotReady
}
