import XCTest

@MainActor
final class ConnectionModelTests: XCTestCase {
    private var tunnel: FakeTunnel!
    private var servers: ServerRepository!
    private var extensionReady = true
    private var model: ConnectionModel!

    override func setUp() async throws {
        tunnel = FakeTunnel()
        servers = ServerRepository(storage: InMemoryServerListStorage(), secrets: InMemorySecretStore(),
                                   configService: FakeConfigService())
        extensionReady = true
        model = ConnectionModel(servers: servers, tunnel: tunnel, isTunnelExtensionReady: { [unowned self] in extensionReady })
    }

    func testConnectStartsTunnelWithParsedClient() async throws {
        let server = try await servers.add(accessKey: "\(testStaticKey)#Home")
        try await model.connect(serverID: server.id)

        XCTAssertEqual(tunnel.started.count, 1)
        XCTAssertEqual(tunnel.started.first?.id, server.id)
        XCTAssertEqual(tunnel.started.first?.name, "Home")
        XCTAssertTrue(tunnel.started.first?.transport.contains(testStaticKey) ?? false)
        XCTAssertEqual(model.activeServerID, server.id)
        XCTAssertNil(model.busyServerID)
    }

    func testConnectNeedsTheExtension() async throws {
        let server = try await servers.add(accessKey: testStaticKey)
        extensionReady = false
        await assertThrows(UserFacingError.self, { try await self.model.connect(serverID: server.id) }) {
            $0.message.contains("VPN component")
        }
        XCTAssertTrue(tunnel.started.isEmpty)
    }

    func testTunnelErrorsBecomeUserFacing() async throws {
        let server = try await servers.add(accessKey: testStaticKey)
        tunnel.startError = KeylineError.platformError(PlaterrorsPlatformErrorMake("ERR_PROXY_SERVER_UNREACHABLE", "dial failed"))
        await assertThrows(UserFacingError.self, { try await self.model.connect(serverID: server.id) }) {
            $0.message == UserFacingError.Message.serverUnreachable && ($0.details ?? "").contains("dial failed")
        }
        XCTAssertNil(model.busyServerID, "busy state is cleared after a failure")
    }

    func testForgettingTheActiveServerDisconnectsFirst() async throws {
        let server = try await servers.add(accessKey: testStaticKey)
        try await model.connect(serverID: server.id)
        await model.forget(serverID: server.id)
        XCTAssertEqual(tunnel.stopped, [server.id])
        XCTAssertTrue(servers.servers.isEmpty)
    }

    func testForgettingAnotherServerLeavesTheTunnel() async throws {
        let active = try await servers.add(accessKey: "\(testStaticKey)#A")
        let other = try await servers.add(accessKey: "ssconf://example.com/b")
        try await model.connect(serverID: active.id)
        await model.forget(serverID: other.id)
        XCTAssertTrue(tunnel.stopped.isEmpty)
        XCTAssertEqual(model.activeServerID, active.id)
    }
}
