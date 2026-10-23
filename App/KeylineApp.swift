import os
import SwiftUI

@main
struct KeylineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var systemExtension: SystemExtensionManager
    @StateObject private var tunnel: TunnelController
    @StateObject private var servers: ServerRepository
    @StateObject private var connection: ConnectionModel
    @StateObject private var stats = StatsSampler()
    @StateObject private var selection = ServerSelection()
    @StateObject private var settings: AppSettings
    @StateObject private var crashReports: CrashReportStore

    init() {
        let systemExtension = SystemExtensionManager()
        let settings = AppSettings()
        let crashReports = CrashReportStore.standard()
        crashReports.startListening()
        _crashReports = StateObject(wrappedValue: crashReports)
        let tunnel = TunnelController()
        tunnel.splitTunnel = settings.splitTunnel
        _settings = StateObject(wrappedValue: settings)
        let storage: ServerListStorage
        do {
            storage = try FileServerListStorage.standard()
        } catch {
            Logger.keyline("app").fault("No Application Support folder, servers won't be saved: \(error.localizedDescription, privacy: .public)")
            storage = InMemoryServerListStorage()
        }
        let servers = ServerRepository(storage: storage, secrets: KeychainSecretStore(), configService: GoCore(),
                                       countryResolver: CountryLookup())
        _systemExtension = StateObject(wrappedValue: systemExtension)
        _tunnel = StateObject(wrappedValue: tunnel)
        _servers = StateObject(wrappedValue: servers)
        _connection = StateObject(wrappedValue: ConnectionModel(
            servers: servers, tunnel: tunnel,
            isTunnelExtensionReady: { [weak systemExtension] in systemExtension?.state == .activated }))
    }

    var body: some Scene {
        WindowGroup {
            RootView(systemExtension: systemExtension, tunnel: tunnel, servers: servers,
                     connection: connection, stats: stats, selection: selection, settings: settings,
                     crashReports: crashReports)
                .onAppear {
                    appDelegate.configure(tunnel: tunnel, settings: settings, servers: servers,
                                          connection: connection, selection: selection)
                    systemExtension.activate()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["*"])
    }
}
