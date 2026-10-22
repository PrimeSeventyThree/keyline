import XCTest

/// Cases from upstream's config.spec.ts and server.ts naming rules.
final class AccessKeyTests: XCTestCase {
    private let go = GoCore()

    func testStaticKeyNameAndConfig() throws {
        let key = try AccessKey("\(testStaticKey)#My%20Server", using: go)
        guard case .static(let name, let config) = key else { return XCTFail("expected a static key") }
        XCTAssertEqual(name, "My Server")
        XCTAssertEqual(config.firstHop, "example.com:4321")
        XCTAssertEqual(config.connectionType, .tunneled)
        XCTAssertTrue(config.client.contains(testStaticKey), "the fragment must not reach the Go core")
    }

    func testNameIgnoresParameters() throws {
        let key = try AccessKey("\(testStaticKey)#foo=bar&My%20Server&baz=boo", using: go)
        XCTAssertEqual(key.name, "My Server")
    }

    func testNoNameWithoutFragmentOrOnlyParameters() throws {
        XCTAssertNil(try AccessKey(testStaticKey, using: go).name)
        XCTAssertNil(try AccessKey("\(testStaticKey)#outline=1", using: go).name)
        XCTAssertNil(try AccessKey("\(testStaticKey)#", using: go).name)
    }

    func testSsconfBecomesHTTPS() throws {
        let key = try AccessKey("ssconf://example.com:4321/path#My%20Server", using: go)
        XCTAssertEqual(key, .dynamic(name: "My Server", configURL: URL(string: "https://example.com:4321/path")!))
    }

    func testHTTPSKeyIsDynamic() throws {
        let key = try AccessKey("https://example.com/config?token=abc", using: go)
        XCTAssertEqual(key, .dynamic(name: nil, configURL: URL(string: "https://example.com/config?token=abc")!))
    }

    func testSurroundingWhitespaceIsIgnored() throws {
        XCTAssertEqual(try AccessKey("  \(testStaticKey)#Name\n", using: go).name, "Name")
    }

    func testRejectsInvalidKeys() {
        for text in ["", "hello", "http://example.com/config", "vmess://abc", "ss://invalid", "ssconf://", "ssconf:///path"] {
            XCTAssertThrowsError(try AccessKey(text, using: go), "accepted \(text)") { error in
                guard case ServerError.invalidAccessKey = error else { return XCTFail("\(text): \(error)") }
            }
        }
    }

    func testDefaultNames() throws {
        func defaultName(_ text: String) throws -> String {
            try AccessKey(text, using: go).defaultName(accessKeyText: text)
        }
        XCTAssertEqual(try defaultName(testStaticKey), "Proxy Server")
        XCTAssertEqual(try defaultName("\(testStaticKey)?outline=1"), "Outline Server")
        XCTAssertEqual(try defaultName("ssconf://example.com/path"), "example.com")
        XCTAssertEqual(try defaultName("ssconf://example.com:443/path"), "example.com")
        XCTAssertEqual(try defaultName("ssconf://example.com:8443/path"), "example.com:8443")
    }
}
