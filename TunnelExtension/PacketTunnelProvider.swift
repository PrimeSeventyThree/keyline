import NetworkExtension
import Tun2socks

/// Phase 0 placeholder. Phase 1 ports upstream's PacketTunnelProvider
/// (client/src/cordova/apple/OutlineLib/VpnExtension/Sources) to Swift.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(NEVPNError(.configurationInvalid))
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// Compile-time check that the Go core links into the extension.
private let goCoreLinkCheck: (String?, String?) -> OutlineInvokeMethodResult? = OutlineInvokeMethod
