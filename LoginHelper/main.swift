import AppKit

// Keyline's login helper for macOS 12 (macOS 13 and later use SMAppService instead).
// macOS starts it at login when the user turns on "Open Keyline at login"; it opens
// Keyline unless it is already running, then quits.

let mainAppID = "ca.pulsbeat.keyline"

guard NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty else { exit(0) }

// Keyline.app/Contents/Library/LoginItems/KeylineLoginHelper.app → Keyline.app
let appURL = (0..<4).reduce(Bundle.main.bundleURL) { url, _ in url.deletingLastPathComponent() }
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in exit(0) }
// Give up if Keyline hasn't opened within a minute.
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { exit(1) }
dispatchMain()
