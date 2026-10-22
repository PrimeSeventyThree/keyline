// Error-to-message mapping ported from Outline's app.ts (showLocalizedError) and
// platform_error.ts (client/web/), Copyright 2024 The Outline Authors, Apache License 2.0.
// Changed by Pulsbeat Media Inc.: rewritten in Swift, more Go error codes mapped,
// "Outline" in messages replaced by "Keyline".

import Foundation
import Tun2socks

/// An error as the user sees it: a localized message and, when there is more to show,
/// technical details for the "Error details" dialog.
struct UserFacingError: Error, Equatable {
    let message: String
    let details: String?

    init(message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }

    init(_ error: Error) {
        switch error {
        case let error as ServerError:
            self = Self.from(error)
        case let error as UserFacingError:
            self = error
        default:
            self = Self.from(KeylineError(error))
        }
    }

    private static func from(_ error: ServerError) -> UserFacingError {
        switch error {
        case .invalidAccessKey(let cause):
            return UserFacingError(message: Message.invalidAccessKey, details: cause.map { KeylineError($0).detailsText })
        case .alreadyAdded(let serverName):
            return UserFacingError(message: String(
                localized: "error-server-already-added",
                defaultValue: "Server “\(serverName)” already added."))
        case .missingAccessKey:
            return UserFacingError(message: Message.invalidAccessKey, details: "The access key is missing from the Keychain.")
        case .emptyDynamicConfig:
            return UserFacingError(message: Message.invalidConfiguration, details: "Got an empty config from the dynamic key.")
        case .proxylessNotSupported:
            return UserFacingError(message: Message.invalidConfiguration, details: "Proxyless connections are not supported.")
        case .tunnelExtensionNotReady:
            return UserFacingError(message: String(
                localized: "error-tunnel-extension-not-ready",
                defaultValue: "Install and allow the Keyline VPN component before connecting."))
        }
    }

    private static func from(_ error: KeylineError) -> UserFacingError {
        let details = error.detailsText
        switch error.code {
        case PlaterrorsProviderError:
            // The provider's own message is meant for the user; its details are optional.
            let platform = PlatformErrorJSON(error.json)
            return UserFacingError(message: platform?.message ?? Message.unexpected, details: platform?.providerDetails)
        case PlaterrorsFetchConfigFailed:
            return UserFacingError(message: Message.fetchConfigFailed, details: details)
        case PlaterrorsInvalidConfig:
            return UserFacingError(message: Message.invalidConfiguration, details: details)
        case PlaterrorsProxyServerUnreachable:
            return UserFacingError(message: Message.serverUnreachable, details: details)
        case PlaterrorsUnauthenticated:
            return UserFacingError(message: Message.invalidCredentials, details: details)
        case PlaterrorsProxyServerUDPUnsupported:
            return UserFacingError(message: Message.udpUnsupported, details: details)
        case PlaterrorsVPNPermissionNotGranted:
            return UserFacingError(message: Message.vpnPermissionNotGranted, details: details)
        case PlaterrorsSetupSystemVPNFailed:
            return UserFacingError(message: Message.systemConfiguration, details: details)
        case PlaterrorsProxyServerReadFailed, PlaterrorsProxyServerWriteFailed,
             PlaterrorsDataTransmissionFailed, PlaterrorsResolveIPFailed:
            return UserFacingError(message: Message.connectionFailed, details: details)
        default:
            return UserFacingError(message: Message.unexpected, details: details)
        }
    }

    /// Message texts, keyed by upstream's message IDs (client/web/messages/en.json) so the
    /// translations can be imported from there.
    enum Message {
        static var invalidAccessKey: String {
            String(localized: "error-invalid-access-key",
                   defaultValue: "Invalid access key. Please try again, or submit feedback for help.")
        }
        static var invalidConfiguration: String {
            String(localized: "error-connection-configuration",
                   defaultValue: "Invalid configuration. Screenshot the error details and send them to your access key provider.")
        }
        static var fetchConfigFailed: String {
            String(localized: "error-connection-configuration-fetch",
                   defaultValue: "Failed to download the server configuration. Screenshot the error details and send them to your access key provider.")
        }
        static var connectionFailed: String {
            String(localized: "error-connection-proxy",
                   defaultValue: "Failed to connect. Please check your internet connectivity, then screenshot the error details and send them to your access key provider.")
        }
        static var serverUnreachable: String {
            String(localized: "outline-plugin-error-server-unreachable",
                   defaultValue: "We can’t seem to connect to your server. Please check that you are connected to the internet and try again.")
        }
        static var invalidCredentials: String {
            String(localized: "outline-plugin-error-invalid-server-credentials",
                   defaultValue: "It seems like your access key is not valid. If this happens again, please contact the person who gave it to you.")
        }
        static var udpUnsupported: String {
            String(localized: "outline-plugin-error-udp-forwarding-not-enabled",
                   defaultValue: "It seems like this server doesn’t support UDP forwarding. If this happens again, please contact the person who gave you access.")
        }
        static var vpnPermissionNotGranted: String {
            String(localized: "outline-plugin-error-vpn-permission-not-granted",
                   defaultValue: "Keyline needs your permission to set up a VPN connection to the server. Please try again, or submit feedback if you need help.")
        }
        static var systemConfiguration: String {
            String(localized: "outline-plugin-error-system-configuration",
                   defaultValue: "Sorry, it looks like Keyline is not properly installed. Please try installing it again. If that doesn't work, please submit feedback through the app.")
        }
        static var unexpected: String {
            String(localized: "error-unexpected",
                   defaultValue: "Sorry, an unexpected error occurred. Quitting and restarting may help. If this happens again, please submit feedback.")
        }
    }
}

extension KeylineError {
    /// The error's JSON details, pretty-printed for the details dialog.
    var detailsText: String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8)
        else { return json }
        return text
    }
}

/// The fields of a Go `PlatformError` JSON the app reads.
private struct PlatformErrorJSON: Decodable {
    let message: String
    let details: [String: AnyDecodableString]?

    init?(_ json: String) {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
        self = value
    }

    /// A provider error keeps its explanation for the user in `details.details`.
    var providerDetails: String? { details?["details"]?.value }
}

/// Decodes a JSON string value and ignores values of any other type.
private struct AnyDecodableString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}
