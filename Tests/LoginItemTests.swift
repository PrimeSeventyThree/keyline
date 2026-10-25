import XCTest

/// `LoginItem` must never call the system on the main thread: SMAppService can block there
/// for seconds and freeze Keyline (#17).
@MainActor
final class LoginItemTests: XCTestCase {
    private final class RecordingService: LoginItemService {
        private let lock = NSLock()
        private var enabled = false
        private var _calledOnMainThread: [Bool] = []
        var calledOnMainThread: [Bool] { lock.lock(); defer { lock.unlock() }; return _calledOnMainThread }

        var isEnabled: Bool {
            lock.lock(); defer { lock.unlock() }
            _calledOnMainThread.append(Thread.isMainThread)
            return enabled
        }

        func setEnabled(_ enabled: Bool) throws {
            lock.lock(); defer { lock.unlock() }
            _calledOnMainThread.append(Thread.isMainThread)
            self.enabled = enabled
        }
    }

    func testCallsTheSystemOffTheMainThread() async throws {
        let service = RecordingService()
        let loginItem = LoginItem(service: service)
        let initiallyEnabled = await loginItem.isEnabled()
        XCTAssertFalse(initiallyEnabled)
        try await loginItem.setEnabled(true)
        let enabled = await loginItem.isEnabled()
        XCTAssertTrue(enabled)
        XCTAssertEqual(service.calledOnMainThread, [false, false, false])
    }

    func testCreatingDoesNotCallTheSystem() {
        let service = RecordingService()
        _ = LoginItem(service: service)
        XCTAssertEqual(service.calledOnMainThread, [])
    }
}
