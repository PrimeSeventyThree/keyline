import Foundation
import ServiceManagement

/// Opens Keyline at login. Each call goes to the system off the main thread: on macOS 13 and
/// later SMAppService asks smd over XPC, which can block for seconds (#17).
struct LoginItem {
    static let helperBundleID = "\(KeylineIdentifiers.app).LoginHelper"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
    }

    func isEnabled() async -> Bool {
        let service = service
        return await Task.detached { service.isEnabled }.value
    }

    func setEnabled(_ enabled: Bool) async throws {
        let service = service
        try await Task.detached { try service.setEnabled(enabled) }.value
    }
}

/// The blocking system calls behind `LoginItem`.
protocol LoginItemService {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// macOS 13 and later register the app itself with SMAppService; macOS 12 enables the
/// KeylineLoginHelper app bundled in Contents/Library/LoginItems, which opens Keyline and quits.
struct SystemLoginItemService: LoginItemService {
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
        guard SMLoginItemSetEnabled(LoginItem.helperBundleID as CFString, enabled) else {
            throw LoginItem.Failure(description: "SMLoginItemSetEnabled(\(LoginItem.helperBundleID), \(enabled)) failed")
        }
        defaults.set(enabled, forKey: legacyKey)
    }
}
