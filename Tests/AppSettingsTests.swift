import XCTest

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "keyline-settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: defaults, domain: suiteName)
    }

    func testDefaults() {
        let settings = makeSettings()
        XCTAssertFalse(settings.stopVPNOnQuit, "the VPN stays on after quitting unless the user asks otherwise")
        XCTAssertTrue(settings.warnOnQuitWhileConnected)
        XCTAssertEqual(settings.language, .system)
        XCTAssertFalse(settings.needsRestartForLanguage)
    }

    func testChangesPersist() {
        let settings = makeSettings()
        settings.stopVPNOnQuit = true
        settings.warnOnQuitWhileConnected = false
        let reopened = makeSettings()
        XCTAssertTrue(reopened.stopVPNOnQuit)
        XCTAssertFalse(reopened.warnOnQuitWhileConnected)
    }

    func testLanguageOverrideNeedsARestart() {
        let settings = makeSettings()
        settings.language = .russian
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ru"])
        XCTAssertTrue(settings.needsRestartForLanguage)

        let relaunched = makeSettings()
        XCTAssertEqual(relaunched.language, .russian)
        XCTAssertFalse(relaunched.needsRestartForLanguage, "after a restart the language is in effect")

        relaunched.language = .system
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"], "System removes the override")
        XCTAssertTrue(relaunched.needsRestartForLanguage)
    }

    func testOnboardingRunsOnce() {
        let settings = makeSettings()
        XCTAssertFalse(settings.hasCompletedOnboarding, "a new install starts with onboarding")
        settings.hasCompletedOnboarding = true
        XCTAssertTrue(makeSettings().hasCompletedOnboarding)
    }

    func testAutoConnectIsExplainedOnce() {
        let settings = makeSettings()
        XCTAssertFalse(settings.hasSeenAutoConnectExplainer)
        settings.hasSeenAutoConnectExplainer = true
        XCTAssertTrue(makeSettings().hasSeenAutoConnectExplainer)
    }

    func testRegionalLanguageCodesMatch() {
        defaults.set(["en-CA"], forKey: "AppleLanguages")
        XCTAssertEqual(makeSettings().language, .english)
    }

    func testQuitDecisions() {
        XCTAssertEqual(QuitDecision.decide(isVPNActive: false, stopVPNOnQuit: true, warnOnQuit: true), .quit,
                       "nothing to ask when the VPN is off")
        XCTAssertEqual(QuitDecision.decide(isVPNActive: true, stopVPNOnQuit: true, warnOnQuit: true), .disconnectThenQuit)
        XCTAssertEqual(QuitDecision.decide(isVPNActive: true, stopVPNOnQuit: false, warnOnQuit: true), .ask)
        XCTAssertEqual(QuitDecision.decide(isVPNActive: true, stopVPNOnQuit: false, warnOnQuit: false), .quit,
                       "after Don't ask again, quitting leaves the VPN on")
    }
}
