import NetworkExtension
import XCTest

final class ErrorTests: XCTestCase {
    func testGoErrorCodesMapToMessages() {
        let cases: [(String, String)] = [
            ("ERR_PROXY_SERVER_UNREACHABLE", UserFacingError.Message.serverUnreachable),
            ("ERR_CLIENT_UNAUTHENTICATED", UserFacingError.Message.invalidCredentials),
            ("ERR_PROXY_SERVER_UDP_NOT_SUPPORTED", UserFacingError.Message.udpUnsupported),
            ("ERR_FETCH_CONFIG_FAILURE", UserFacingError.Message.fetchConfigFailed),
            ("ERR_INVALID_CONFIG", UserFacingError.Message.invalidConfiguration),
            ("ERR_VPN_PERMISSION_NOT_GRANTED", UserFacingError.Message.vpnPermissionNotGranted),
            ("ERR_SYSTEM_VPN_SETUP_FAILURE", UserFacingError.Message.systemConfiguration),
            ("ERR_DATA_TRANSMISSION_FAILURE", UserFacingError.Message.connectionFailed),
            ("ERR_INTERNAL_ERROR", UserFacingError.Message.unexpected),
            ("ERR_SOMETHING_NEW", UserFacingError.Message.unexpected),
        ]
        for (code, message) in cases {
            let error = KeylineError.platformError(PlaterrorsPlatformErrorMake(code, "boom"))
            let shown = UserFacingError(error)
            XCTAssertEqual(shown.message, message, code)
            XCTAssertTrue(shown.details?.contains("boom") ?? false, "\(code) keeps the details")
        }
    }

    func testProviderErrorShowsProviderText() throws {
        // From upstream's Test_doParseTunnelConfig_ProviderErrorJSON.
        let json = #"{"error":{"message":"⚠ Invalid Access Key","details":"⚠ Details"}}"#
        XCTAssertThrowsError(try GoCore().parseTunnelConfig(json)) { error in
            XCTAssertEqual(KeylineError(error).code, "ERR_PROVIDER")
            XCTAssertEqual(UserFacingError(error), UserFacingError(message: "⚠ Invalid Access Key", details: "⚠ Details"))
        }
    }

    func testKeylineErrorSurvivesNSErrorRoundTrip() {
        // The extension cancels the tunnel with a KeylineError; the app gets it back as an NSError.
        let original = KeylineError.platformError(PlaterrorsPlatformErrorMake("ERR_CLIENT_UNAUTHENTICATED", "bad password"))
        let nsError = NSError(domain: KeylineError.errorDomain, code: 1, userInfo: (original as NSError).userInfo)
        let restored = KeylineError(nsError)
        XCTAssertEqual(restored.code, "ERR_CLIENT_UNAUTHENTICATED")
        XCTAssertEqual(restored.json, original.json)
    }

    func testForeignErrorsAreInternal() {
        let error = KeylineError(NEVPNError(.configurationInvalid))
        XCTAssertEqual(error.code, "ERR_INTERNAL_ERROR")
    }

    func testServerErrorsBecomeUserFacing() {
        XCTAssertEqual(UserFacingError(ServerError.alreadyAdded(serverName: "Home")).message, "Server “Home” already added.")
        XCTAssertEqual(UserFacingError(ServerError.invalidAccessKey(cause: nil)).message, UserFacingError.Message.invalidAccessKey)
        XCTAssertEqual(UserFacingError(ServerError.proxylessNotSupported).message, UserFacingError.Message.invalidConfiguration)
    }

    func testDetailsArePrettyPrinted() {
        let error = KeylineError.platformError(PlaterrorsPlatformErrorMake("ERR_INVALID_CONFIG", "bad yaml"))
        XCTAssertTrue(error.detailsText.contains("\n"), error.detailsText)
        XCTAssertTrue(error.detailsText.contains(#""code" : "ERR_INVALID_CONFIG""#), error.detailsText)
    }
}
