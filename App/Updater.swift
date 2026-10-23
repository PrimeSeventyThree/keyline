import Combine
import Sparkle

/// Sparkle auto-updates from the appcast on GitHub Releases (SUFeedURL in Info.plist), signed
/// with Keyline's EdDSA key (SUPublicEDKey). Debug builds don't check, so development builds
/// aren't offered releases.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController

    init() {
        #if DEBUG
        let starts = false
        #else
        let starts = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: starts, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
