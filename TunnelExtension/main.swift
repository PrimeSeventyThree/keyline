import Foundation
import NetworkExtension

// Entry point of the system extension: hand control to NetworkExtension, which
// instantiates PacketTunnelProvider (named in Info.plist) when a tunnel starts.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
