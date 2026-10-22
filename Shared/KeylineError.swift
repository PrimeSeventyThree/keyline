// Ported from Outline's OutlineError.swift
// (client/src/cordova/apple/OutlineAppleLib/Sources/OutlineError/OutlineError.swift),
// Copyright 2024 The Outline Authors, Apache License 2.0. Changed by Pulsbeat Media Inc.:
// renamed, error domain changed, simplified.

import Foundation
import Tun2socks

private enum KeylineErrorUserInfoKey {
    static let code = "KeylineErrorCode"
    static let json = "KeylineErrorJson"
}

/// Errors passed between the tunnel extension and the app. Each one carries a Go
/// `platerrors` code and the error details as JSON, so they survive the trip through
/// `NSError` (cancelTunnelWithError → fetchLastDisconnectError).
enum KeylineError: Error, CustomNSError {
    case detailedJsonError(code: String, json: String)
    case platformError(PlaterrorsPlatformError)
    case internalError(message: String)
    case invalidConfig(message: String)
    case vpnPermissionNotGranted(cause: Error)
    case setupSystemVPNFailed(cause: Error)

    var code: String {
        switch self {
        case .detailedJsonError(let code, _): return code
        case .platformError(let error): return error.code
        case .internalError: return PlaterrorsInternalError
        case .invalidConfig: return PlaterrorsInvalidConfig
        case .vpnPermissionNotGranted: return PlaterrorsVPNPermissionNotGranted
        case .setupSystemVPNFailed: return PlaterrorsSetupSystemVPNFailed
        }
    }

    /// Error details as JSON, in the format of Go's `platerrors.MarshalJSONString`.
    var json: String {
        switch self {
        case .detailedJsonError(_, let json):
            return json
        case .platformError(let error):
            var marshalError: NSError?
            let json = PlaterrorsMarshalJSONString(error, &marshalError)
            return marshalError == nil ? json : "error code = \(code), failed to fetch details"
        case .internalError(let message), .invalidConfig(let message):
            return Self.json(code: code, message: message)
        case .vpnPermissionNotGranted(let cause), .setupSystemVPNFailed(let cause):
            return Self.json(code: code, message: cause.localizedDescription)
        }
    }

    static var errorDomain: String { "\(KeylineIdentifiers.app).error" }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: code,
            KeylineErrorUserInfoKey.code: code,
            KeylineErrorUserInfoKey.json: json,
        ]
    }

    /// Recovers a `KeylineError` from any error, including one that crossed the process
    /// boundary as a plain `NSError`.
    init(_ error: Error) {
        if let error = error as? KeylineError {
            self = error
            return
        }
        let nsError = error as NSError
        guard let json = nsError.userInfo[KeylineErrorUserInfoKey.json] as? String else {
            self = .internalError(message: error.localizedDescription)
            return
        }
        let code = nsError.userInfo[KeylineErrorUserInfoKey.code] as? String ?? PlaterrorsInternalError
        self = .detailedJsonError(code: code, json: json)
    }

    private static func json(code: String, message: String) -> String {
        guard let error = PlaterrorsPlatformError(code, message: message) else {
            return "error code = \(code), message = \(message)"
        }
        return KeylineError.platformError(error).json
    }
}
