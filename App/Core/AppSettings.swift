import Foundation

/// User settings kept in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    enum Language: String, CaseIterable, Identifiable {
        case system, english = "en", russian = "ru"
        var id: String { rawValue }
    }

    /// Disconnect the VPN when quitting. Off by default: the VPN keeps protecting traffic
    /// after Keyline quits, and on-demand reconnects it after a restart.
    @Published var stopVPNOnQuit: Bool {
        didSet { defaults.set(stopVPNOnQuit, forKey: Key.stopVPNOnQuit) }
    }
    /// Ask before quitting while connected (when not disconnecting automatically).
    @Published var warnOnQuitWhileConnected: Bool {
        didSet { defaults.set(warnOnQuitWhileConnected, forKey: Key.warnOnQuit) }
    }
    /// The first-run screens (privacy note, VPN component, first server) are done.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }
    /// The one-time explanation of auto-connect was shown, after the first connection.
    @Published var hasSeenAutoConnectExplainer: Bool {
        didSet { defaults.set(hasSeenAutoConnectExplainer, forKey: Key.autoConnectExplainer) }
    }
    /// The app's language. Takes effect after a restart.
    @Published var language: Language {
        didSet { applyLanguage() }
    }
    /// The language the app is running in, to tell whether a restart is needed.
    let launchLanguage: Language

    private let defaults: UserDefaults
    private enum Key {
        static let stopVPNOnQuit = "stopVPNOnQuit"
        static let warnOnQuit = "warnOnQuitWhileConnected"
        static let onboarding = "hasCompletedOnboarding"
        static let autoConnectExplainer = "hasSeenAutoConnectExplainer"
        /// The standard per-app language override.
        static let appleLanguages = "AppleLanguages"
    }

    /// `domain` is the defaults domain `defaults` writes to: the bundle ID for the standard
    /// defaults, or the suite name in tests. Reading AppleLanguages through `defaults` would
    /// also return the system-wide list, so only the app's own domain says whether the user
    /// chose a language.
    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? KeylineIdentifiers.app) {
        self.defaults = defaults
        stopVPNOnQuit = defaults.object(forKey: Key.stopVPNOnQuit) as? Bool ?? false
        warnOnQuitWhileConnected = defaults.object(forKey: Key.warnOnQuit) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        hasSeenAutoConnectExplainer = defaults.bool(forKey: Key.autoConnectExplainer)
        let chosen = (defaults.persistentDomain(forName: domain)?[Key.appleLanguages] as? [String])?.first
        let language = chosen.flatMap { code in Language.allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } } ?? .system
        self.language = language
        launchLanguage = language
    }

    var needsRestartForLanguage: Bool { language != launchLanguage }

    private func applyLanguage() {
        if language == .system {
            defaults.removeObject(forKey: Key.appleLanguages)
        } else {
            defaults.set([language.rawValue], forKey: Key.appleLanguages)
        }
    }
}

/// What to do when the user quits.
enum QuitDecision: Equatable {
    case quit
    /// Disconnect first, then quit.
    case disconnectThenQuit
    /// Ask whether to leave the VPN on.
    case ask

    static func decide(isVPNActive: Bool, stopVPNOnQuit: Bool, warnOnQuit: Bool) -> QuitDecision {
        guard isVPNActive else { return .quit }
        if stopVPNOnQuit { return .disconnectThenQuit }
        return warnOnQuit ? .ask : .quit
    }
}
