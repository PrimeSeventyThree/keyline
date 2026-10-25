import SwiftUI
import XCTest

/// Renders views to PNG files for design review. Skipped unless KEYLINE_SNAPSHOT_DIR is
/// set; scripts/snapshots.sh sets it.
@MainActor
final class Snapshots: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["KEYLINE_SNAPSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set KEYLINE_SNAPSHOT_DIR to render snapshots")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testFlagContactSheet() throws {
        let codes = flagCodes()
        XCTAssertGreaterThan(codes.count, 240)
        let rows = stride(from: 0, to: codes.count, by: 18).map { Array(codes[$0..<min($0 + 18, codes.count)]) }
        // ImageRenderer doesn't lay out lazy grids, so build plain rows.
        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { code in
                        VStack(spacing: 2) {
                            Image(Country(code: code)!.flagAssetName, bundle: .keylineResources)
                                .resizable()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                            Text(code).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.13, blue: 0.12))
        try render(sheet, named: "flags")
    }

    // MARK: - Screens

    private static let windowSize = CGSize(width: 1120, height: 720)
    /// A large window, to check that the layout scales (#24).
    private static let largeWindowSize = CGSize(width: 1680, height: 1050)

    private func window<Content: View>(_ section: MainSection, connected: Bool, size: CGSize = windowSize,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        MainWindow(section: .constant(section), isConnected: connected) { content() }
            .frame(width: size.width, height: size.height)
    }

    func testLargeWindow() throws {
        let size = Self.largeWindowSize
        try render(window(.connect, connected: true, size: size) { ConnectScreen(state: SampleData.connected) },
                   named: "11a-large-connect")
        let servers = ServersScreenState(servers: SampleData.servers, activeServerID: SampleData.toronto.id, phase: .connected)
        try render(window(.servers, connected: true, size: size) { ServersScreen(state: servers) }, named: "11b-large-servers")
        var settings = SettingsScreenState(launchAtLogin: true)
        let binding = Binding(get: { settings }, set: { settings = $0 })
        try render(window(.settings, connected: true, size: size) { SettingsScreen(state: binding) }, named: "11c-large-settings")
    }

    func testConnectConnected() throws {
        try render(window(.connect, connected: true) { ConnectScreen(state: SampleData.connected) }, named: "1-connect-connected")
    }

    func testConnectDisconnected() throws {
        try render(window(.connect, connected: false) { ConnectScreen(state: SampleData.disconnected) }, named: "2-connect-disconnected")
    }

    func testConnectNeedsApproval() throws {
        var state = SampleData.disconnected
        state.setupNotice = SetupNotice(
            message: "Allow Keyline Tunnel in System Settings › General › Login Items & Extensions › Network Extensions.",
            actionTitle: "Open System Settings")
        try render(window(.connect, connected: false) { ConnectScreen(state: state) }, named: "2c-connect-needs-approval")
    }

    func testConnectConnecting() throws {
        try render(window(.connect, connected: false) { ConnectScreen(state: SampleData.connecting) }, named: "3-connect-connecting")
    }

    func testServers() throws {
        let state = ServersScreenState(servers: SampleData.servers, activeServerID: SampleData.toronto.id, phase: .connected)
        try render(window(.servers, connected: true) { ServersScreen(state: state) }, named: "4-servers")
    }

    func testServersEmpty() throws {
        try render(window(.servers, connected: false) { ServersScreen(state: ServersScreenState()) }, named: "5-servers-empty")
    }

    func testSettings() throws {
        var state = SettingsScreenState(launchAtLogin: true, language: .russian, languageNeedsRestart: true)
        let binding = Binding(get: { state }, set: { state = $0 })
        try render(window(.settings, connected: true) { SettingsScreen(state: binding) }, named: "6-settings")
    }

    func testOnboarding() throws {
        func screen(_ step: OnboardingScreen.Step, _ state: SystemExtensionManager.State,
                    key: String = "", error: String? = nil) -> some View {
            OnboardingScreen(step: step, extensionState: state, accessKey: .constant(key), addServerError: error)
                .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        }
        try render(screen(.welcome, .activating), named: "8a-onboarding-welcome")
        try render(screen(.vpnComponent, .needsApproval), named: "8b-onboarding-approve")
        try render(screen(.vpnComponent, .activated), named: "8c-onboarding-installed")
        try render(screen(.addServer, .activated, key: "ss://not-a-valid-key", error: UserFacingError.Message.invalidAccessKey),
                   named: "8d-onboarding-add-server")
    }

    func testSplitTunnelSheet() throws {
        let settings = SplitTunnelSettings(mode: .exclude, entries: ["192.168.50.0/24", "203.0.113.7", "bank.example.com"])
        try render(SplitTunnelSheet(settings: .constant(settings)), named: "9-split-tunneling")
    }

    func testReportSheet() throws {
        let sheet = ReportSheet(description: .constant("Keyline quit when I switched servers from the menu bar."),
                                includeCrashReports: .constant(true), crashReportCount: 2)
        try render(sheet, named: "10-report")
    }

    func testAddServerSheet() throws {
        let sheet = AddServerSheet(accessKey: .constant("ss://not-a-valid-key"),
                                   errorMessage: UserFacingError.Message.invalidAccessKey)
        try render(sheet, named: "7-add-server")
    }

    // MARK: - Helpers

    /// Region codes macOS knows that have a flag in the compiled bundle. (The test process
    /// can't read the repo when it lives on an external volume, so ask the bundle.)
    private func flagCodes() -> [String] {
        Locale.Region.isoRegions.map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .filter { Bundle.keylineResources.image(forResource: "Flags/\($0.lowercased())") != nil }
            .sorted()
    }

    func render<V: View>(_ view: V, named name: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.isSnapshotRendering, true))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.nsImage, "rendering \(name) failed")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
