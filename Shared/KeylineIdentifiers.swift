// Identifiers shared by the app and the tunnel system extension.
// Changing any of these after release breaks Keychain items, the installed
// system extension and existing VPN configurations, so treat them as fixed.

enum KeylineIdentifiers {
    static let teamID = "49DY4CP2B4"
    static let app = "ca.pulsbeat.keyline"
    static let tunnelExtension = "ca.pulsbeat.keyline.tunnel"
    static let appGroup = "\(teamID).group.ca.pulsbeat.keyline"
}
