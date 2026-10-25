import XCTest

/// Cases from upstream's outline_server_repository.spec.ts and server.ts, plus Keychain
/// and persistence behaviour specific to Keyline.
@MainActor
final class ServerRepositoryTests: XCTestCase {
    private var storage: InMemoryServerListStorage!
    private var secrets: InMemorySecretStore!
    private var service: FakeConfigService!
    private var repository: ServerRepository!

    override func setUp() async throws {
        storage = InMemoryServerListStorage()
        secrets = InMemorySecretStore()
        service = FakeConfigService()
        repository = makeRepository()
    }

    private func makeRepository() -> ServerRepository {
        ServerRepository(storage: storage, secrets: secrets, configService: service)
    }

    // MARK: - Adding

    func testAddStoresServerAndKeySeparately() async throws {
        let server = try await repository.add(accessKey: "\(testStaticKey)#Home")
        XCTAssertEqual(server.name, "Home")
        XCTAssertEqual(server.kind, .static)
        XCTAssertEqual(server.address, "example.com:4321")
        XCTAssertEqual(repository.servers, [server])
        XCTAssertEqual(storage.servers, [server], "the list is saved")
        XCTAssertEqual(secrets.secrets[server.id], "\(testStaticKey)#Home", "the key goes to the secret store")
        XCTAssertFalse(String(describing: storage.servers).contains("Y2hh"), "the saved list holds no key")
    }

    func testAddUsesDefaultNames() async throws {
        let proxy = try await repository.add(accessKey: testStaticKey)
        let dynamic = try await repository.add(accessKey: "ssconf://example.com:8443/c")
        XCTAssertEqual(proxy.name, "Proxy Server")
        XCTAssertEqual(dynamic.name, "example.com:8443")
        XCTAssertEqual(dynamic.kind, .dynamic)
        XCTAssertEqual(service.fetched, [], "adding a dynamic key doesn't download its config")
    }

    func testAddRejectsDuplicates() async throws {
        try await repository.add(accessKey: "\(testStaticKey)#First")
        await assertThrows(ServerError.self, { try await self.repository.add(accessKey: "  \(self.testKeyWithName("First"))  ") }) {
            if case .alreadyAdded("First") = $0 { return true }
            return false
        }
        XCTAssertEqual(repository.servers.count, 1)
    }

    func testAddRejectsInvalidKeys() async {
        await assertThrows(ServerError.self, { try await self.repository.add(accessKey: "ss://invalid") }) {
            if case .invalidAccessKey = $0 { return true }
            return false
        }
        XCTAssertTrue(repository.servers.isEmpty)
        XCTAssertTrue(secrets.secrets.isEmpty)
    }

    // MARK: - Renaming and forgetting

    func testRename() async throws {
        let server = try await repository.add(accessKey: testStaticKey)
        repository.rename(id: server.id, to: "  Office  ")
        XCTAssertEqual(repository.servers.first?.name, "Office")
        XCTAssertEqual(storage.servers.first?.name, "Office")

        repository.rename(id: server.id, to: "   ")
        XCTAssertEqual(repository.servers.first?.name, "Office", "blank names are ignored")
    }

    func testForgetAndUndo() async throws {
        let first = try await repository.add(accessKey: "\(testStaticKey)#A")
        let second = try await repository.add(accessKey: "ssconf://example.com/b#B")
        let third = try await repository.add(accessKey: "ssconf://example.com/c#C")

        repository.forget(id: second.id)
        XCTAssertEqual(repository.servers.map(\.id), [first.id, third.id])
        XCTAssertEqual(storage.servers.map(\.id), [first.id, third.id])
        XCTAssertNil(secrets.secrets[second.id], "forgetting deletes the key")

        repository.undoForget(id: first.id)
        XCTAssertEqual(repository.servers.count, 2, "undo only restores the last forgotten server")

        repository.undoForget(id: second.id)
        XCTAssertEqual(repository.servers.map(\.id), [first.id, second.id, third.id], "undo restores the position")
        XCTAssertEqual(secrets.secrets[second.id], "ssconf://example.com/b#B")
        XCTAssertEqual(storage.servers.count, 3)

        repository.undoForget(id: second.id)
        XCTAssertEqual(repository.servers.count, 3, "undo works once")
    }

    func testForgetErasesGoServiceStorage() async throws {
        let server = try await repository.add(accessKey: testStaticKey)
        repository.forget(id: server.id)
        for _ in 0..<50 where service.erased.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(service.erased, [server.id])
    }

    // MARK: - Loading

    func testDuplicateCheckDoesNotReadTheKeychain() async throws {
        let server = try await repository.add(accessKey: testStaticKey)
        let reloaded = makeRepository()
        try secrets.deleteSecret(for: server.id)
        XCTAssertEqual(reloaded.server(withAccessKey: " \(testStaticKey)\n")?.id, server.id,
                       "keys loaded at launch are kept, so lookups don't query the Keychain")
    }

    func testLoadDropsServersWithoutKeys() async throws {
        let kept = try await repository.add(accessKey: "\(testStaticKey)#Kept")
        let lost = try await repository.add(accessKey: "ssconf://example.com/x#Lost")
        try secrets.deleteSecret(for: lost.id)

        XCTAssertEqual(makeRepository().servers, [kept])
    }

    func testFileStorageRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = FileServerListStorage(fileURL: folder.appendingPathComponent("servers.json"))

        XCTAssertEqual(try file.load(), [], "a missing file is an empty list")
        let servers = [
            Server(id: "1", name: "Home", kind: .static, address: "example.com:4321"),
            Server(id: "2", name: "Сервер", kind: .dynamic, address: ""),
        ]
        try file.save(servers)
        XCTAssertEqual(try file.load(), servers)
    }

    // MARK: - Tunnel configs

    func testStaticTunnelConfig() async throws {
        let server = try await repository.add(accessKey: testStaticKey)
        let config = try await repository.tunnelConfig(forServer: server.id)
        XCTAssertEqual(config.firstHop, "example.com:4321")
        XCTAssertTrue(config.client.contains(testStaticKey))
    }

    func testDynamicTunnelConfigIsFetchedAndUpdatesAddress() async throws {
        let server = try await repository.add(accessKey: "ssconf://config.example.com/key#Dyn")
        let url = URL(string: "https://config.example.com/key")!
        service.setResponse("\n\(testStaticKey)\n", for: url)

        let config = try await repository.tunnelConfig(forServer: server.id)
        XCTAssertEqual(service.fetched, [url])
        XCTAssertEqual(config.firstHop, "example.com:4321")
        XCTAssertEqual(repository.servers.first?.address, "example.com:4321")
        XCTAssertEqual(storage.servers.first?.address, "example.com:4321")
    }

    func testDynamicEmptyConfig() async throws {
        let server = try await repository.add(accessKey: "ssconf://config.example.com/empty")
        service.setResponse("  \n", for: URL(string: "https://config.example.com/empty")!)
        await assertThrows(ServerError.self, { _ = try await self.repository.tunnelConfig(forServer: server.id) }) {
            if case .emptyDynamicConfig = $0 { return true }
            return false
        }
    }

    func testDynamicProviderError() async throws {
        let server = try await repository.add(accessKey: "ssconf://config.example.com/expired")
        service.setResponse("error:\n  message: Unauthorized\n  details: Account expired\n",
                            for: URL(string: "https://config.example.com/expired")!)
        do {
            _ = try await repository.tunnelConfig(forServer: server.id)
            XCTFail("expected a provider error")
        } catch {
            let shown = UserFacingError(error)
            XCTAssertEqual(shown.message, "Unauthorized", "the provider's message is shown as is")
            XCTAssertEqual(shown.details, "Account expired")
        }
    }

    func testRejectsProxylessConfigs() async throws {
        let server = try await repository.add(accessKey: "ssconf://config.example.com/direct")
        service.setResponse("transport:\n  $type: tcpudp\n  tcp:\n  udp:\n", for: URL(string: "https://config.example.com/direct")!)
        await assertThrows(ServerError.self, { _ = try await self.repository.tunnelConfig(forServer: server.id) }) {
            if case .proxylessNotSupported = $0 { return true }
            return false
        }
    }

    func testMissingKey() async throws {
        let server = try await repository.add(accessKey: testStaticKey)
        try secrets.deleteSecret(for: server.id)
        await assertThrows(ServerError.self, { _ = try await self.repository.tunnelConfig(forServer: server.id) }) {
            if case .missingAccessKey = $0 { return true }
            return false
        }
    }

    private func testKeyWithName(_ name: String) -> String { "\(testStaticKey)#\(name)" }
}
