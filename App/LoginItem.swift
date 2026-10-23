import Foundation
import ServiceManagement

/// Opens Keyline at login. macOS 13 and later register the app itself with SMAppService;
/// macOS 12 enables the KeylineLoginHelper app bundled in Contents/Library/LoginItems,
/// which opens Keyline and quits.
struct LoginItem {
    static let helperBundleID = "\(KeylineIdentifiers.app).LoginHelper"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let defaults: UserDefaults
    /// macOS 12 has no API to ask whether the helper is enabled, so remember it.
    private let legacyKey = "launchAtLogin"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return defaults.bool(forKey: legacyKey)
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return
        }
        guard SMLoginItemSetEnabled(Self.helperBundleID as CFString, enabled) else {
            throw Failure(description: "SMLoginItemSetEnabled(\(Self.helperBundleID), \(enabled)) failed")
        }
        defaults.set(enabled, forKey: legacyKey)
    }
}
