import XCTest

@MainActor
final class AccessKeyDetectionTests: XCTestCase {
    func testRecognisesAccessKeys() {
        XCTAssertEqual(AccessKeyDetection.candidate(in: "  \(testStaticKey)#Home\n"), "\(testStaticKey)#Home")
        XCTAssertEqual(AccessKeyDetection.candidate(in: "ssconf://example.com/key"), "ssconf://example.com/key")
        XCTAssertEqual(AccessKeyDetection.candidate(in: "SS://abc"), "SS://abc", "the scheme is case-insensitive")
    }

    func testIgnoresOtherText() {
        XCTAssertNil(AccessKeyDetection.candidate(in: nil))
        XCTAssertNil(AccessKeyDetection.candidate(in: ""))
        XCTAssertNil(AccessKeyDetection.candidate(in: "https://example.com"), "https keys must be pasted, not detected")
        XCTAssertNil(AccessKeyDetection.candidate(in: "my key is ss://abc"))
        XCTAssertNil(AccessKeyDetection.candidate(in: "ss://abc\nss://def"), "several lines are not one key")
    }

    func testClipboardOffersEachCopyOnce() {
        let watcher = ClipboardWatcher()
        XCTAssertEqual(watcher.newAccessKey(changeCount: 1, text: testStaticKey, isAlreadyAdded: { _ in false }), testStaticKey)
        XCTAssertNil(watcher.newAccessKey(changeCount: 1, text: testStaticKey, isAlreadyAdded: { _ in false }),
                     "the same copy isn't offered again")
        XCTAssertEqual(watcher.newAccessKey(changeCount: 2, text: testStaticKey, isAlreadyAdded: { _ in false }), testStaticKey,
                       "copying it again counts as a new copy")
    }

    func testClipboardSkipsAddedKeysAndOtherText() {
        let watcher = ClipboardWatcher()
        XCTAssertNil(watcher.newAccessKey(changeCount: 1, text: testStaticKey, isAlreadyAdded: { _ in true }))
        XCTAssertNil(watcher.newAccessKey(changeCount: 2, text: "hello", isAlreadyAdded: { _ in false }))
    }

    func testFindsServersByAccessKey() async throws {
        let repository = ServerRepository(storage: InMemoryServerListStorage(), secrets: InMemorySecretStore(),
                                          configService: FakeConfigService())
        let server = try await repository.add(accessKey: "\(testStaticKey)#Home")
        XCTAssertEqual(repository.server(withAccessKey: " \(testStaticKey)#Home ")?.id, server.id)
        XCTAssertNil(repository.server(withAccessKey: testStaticKey), "a different fragment is a different key")
    }
}
