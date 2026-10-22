import Foundation
import NetworkExtension
import Tun2socks
import XCTest

/// Static test key from upstream's parse_test.go: chacha20-ietf-poly1305 with password
/// "SECRET" at example.com:4321. Not a real server.
let testStaticKey = "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpTRUNSRVQ@example.com:4321/"

/// Parses with the real Go core, and serves dynamic configs from a table instead of the
/// network.
final class FakeConfigService: TunnelConfigService, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: String] = [:]
    private var _fetched: [URL] = []
    private var _erased: [String] = []

    var fetched: [URL] { lock.lock(); defer { lock.unlock() }; return _fetched }
    var erased: [String] { lock.lock(); defer { lock.unlock() }; return _erased }

    func setResponse(_ body: String, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        responses[url] = body
    }

    func parseTunnelConfig(_ text: String) throws -> TunnelConfig {
        try GoCore().parseTunnelConfig(text)
    }

    func fetchResource(_ url: URL) throws -> String {
        lock.lock(); defer { lock.unlock() }
        _fetched.append(url)
        guard let body = responses[url] else {
            throw KeylineError.platformError(PlaterrorsPlatformErrorMake("ERR_FETCH_CONFIG_FAILURE", "no response for \(url)"))
        }
        return body
    }

    func eraseServiceStorage(serverID: String) throws {
        lock.lock(); defer { lock.unlock() }
        _erased.append(serverID)
    }
}

/// Records what `ConnectionModel` asks of the tunnel.
@MainActor
final class FakeTunnel: TunnelControlling {
    var status: NEVPNStatus = .disconnected
    var tunnelID: String?
    var startError: Error?
    private(set) var started: [(id: String, name: String, transport: String)] = []
    private(set) var stopped: [String] = []

    func start(id: String, name: String, transport: String) async throws {
        if let startError { throw startError }
        started.append((id, name, transport))
        tunnelID = id
        status = .connected
    }

    func stop(id: String) async {
        stopped.append(id)
        status = .disconnected
    }
}

/// Builds a Go `PlatformError`, which gomobile exposes with a failable initializer.
func PlaterrorsPlatformErrorMake(_ code: String, _ message: String) -> PlaterrorsPlatformError {
    PlaterrorsPlatformError(code, message: message)!
}

/// Asserts that `body` throws an error of type `E` matching `check`.
func assertThrows<E: Error>(
    _ type: E.Type, file: StaticString = #filePath, line: UInt = #line,
    _ body: () async throws -> Void, check: (E) -> Bool = { _ in true }
) async {
    do {
        try await body()
        XCTFail("Expected \(E.self), but nothing was thrown", file: file, line: line)
    } catch let error as E {
        XCTAssertTrue(check(error), "Unexpected \(error)", file: file, line: line)
    } catch {
        XCTFail("Expected \(E.self), got \(error)", file: file, line: line)
    }
}
