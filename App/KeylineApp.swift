import os
import SwiftUI

@main
struct KeylineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var systemExtension: SystemExtensionManager
    @StateObject private var tunnel: TunnelController
    @StateObject private var servers: ServerRepository
    @StateObject private var connection: ConnectionModel

    init() {
        let systemExtension = SystemExtensionManager()
        let tunnel = TunnelController()
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
            ContentView(systemExtension: systemExtension, tunnel: tunnel, servers: servers, connection: connection)
                .onAppear { systemExtension.activate() }
        }
    }
}
