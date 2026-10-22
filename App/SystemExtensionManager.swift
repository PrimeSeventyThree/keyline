import AppKit
import os
import SystemExtensions

/// Installs (activates) the tunnel system extension and tracks whether it is ready.
/// Activating an installed extension is cheap, and replaces it after an app update, so
/// the app requests activation on every launch.
@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {
    enum State: Equatable {
        case unknown
        case activating
        /// macOS is waiting for the user to allow the extension in System Settings.
        case needsApproval
        case activated
        /// Activation only works for apps in /Applications.
        case notInApplications
        case failed(String)
    }

    @Published private(set) var state: State = .unknown
    private let log = Logger.keyline("sysext")

    func activate() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            state = .notInApplications
            return
        }
        state = .activating
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: KeylineIdentifiers.tunnelExtension, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Where the user allows the extension, which moved between macOS versions.
    static var approvalLocation: String {
        if #available(macOS 15, *) {
            return String(localized: "System Settings › General › Login Items & Extensions › Network Extensions")
        } else if #available(macOS 13, *) {
            return String(localized: "System Settings › Privacy & Security")
        } else {
            return String(localized: "System Preferences › Security & Privacy › General")
        }
    }

    /// Opens the settings pane named by `approvalLocation`.
    func openApprovalSettings() {
        let pane: String
        if #available(macOS 15, *) {
            pane = "com.apple.LoginItems-Settings.extension"
        } else if #available(macOS 13, *) {
            pane = "com.apple.settings.PrivacySecurity.extension"
        } else {
            pane = "com.apple.preference.security?General"
        }
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Removes the extension. macOS asks the user to confirm.
    func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: KeylineIdentifiers.tunnelExtension, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

// The requests above use the main queue, so the delegate callbacks arrive on the main thread.
extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        Logger.keyline("sysext").info(
            "Replacing extension \(existing.bundleShortVersion) (\(existing.bundleVersion)) with \(ext.bundleShortVersion) (\(ext.bundleVersion))")
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        MainActor.assumeIsolated {
            log.info("Extension request finished: \(result.rawValue)")
            // .willCompleteAfterReboot only happens for deactivation or replacement.
            state = result == .completed ? .activated : .unknown
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            log.error("Extension request failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }
}
