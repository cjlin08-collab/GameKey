import SwiftUI
import Combine

@main
struct GameKeyApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .frame(minWidth: 900, minHeight: 600)
                .task { await environment.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Bottles") {
                Button("Open Bottles Folder") { environment.openBottlesFolder() }
                Button("Reveal GPTK Wine Binary") { environment.revealWineBinary() }
            }
        }

        Settings {
            SettingsView().environmentObject(environment)
        }
    }
}

/// Top-level shared state. Owns the long-lived services so views can pull them via @EnvironmentObject.
@MainActor
final class AppEnvironment: ObservableObject {
    let gptk = GPTKManager()
    let bottles = BottleManager()
    let installer: LauncherInstaller
    let license = LicenseManager()
    let thermal = ThermalMonitor()
    @Published var initialized = false
    @Published var gptkStatus: GPTKManager.Status = .unknown

    private var cancellables = Set<AnyCancellable>()
    private var thermalReniceTimer: Timer?

    init() {
        self.installer = LauncherInstaller(bottles: bottles, gptk: gptk)
        // Forward child @Published changes up so any view bound to AppEnvironment rebuilds.
        bottles.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        installer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        gptk.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        license.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        thermal.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // When thermal pressure goes serious or worse and the user opted in to throttling,
        // periodically renice wine processes. Cheap and safe.
        thermal.$level
            .sink { [weak self] level in
                self?.handleThermalChange(level)
            }
            .store(in: &cancellables)
    }

    private func handleThermalChange(_ level: ThermalMonitor.Level) {
        guard thermal.throttleWineProcesses else { return }
        if level == .serious || level == .critical {
            thermal.reniceWineProcesses()
            // Re-renice every 30s while still hot — wine spawns new subprocesses.
            thermalReniceTimer?.invalidate()
            thermalReniceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.thermal.reniceWineProcesses() }
            }
        } else {
            thermalReniceTimer?.invalidate()
            thermalReniceTimer = nil
        }
    }

    func bootstrap() async {
        // License check first — if the key is bad we don't want to spin up bottles or hit GPTK.
        await license.bootstrap()
        guard license.isLicensed else {
            initialized = true
            return
        }
        await bottles.loadFromDisk()
        gptkStatus = await gptk.detect()
        initialized = true
    }

    /// Called from RootView once the user pastes a valid key on a fresh install: we deferred the
    /// expensive setup until we knew the key was good.
    func completeBootstrapAfterLicense() async {
        guard license.isLicensed, !initialized else { return }
        await bottles.loadFromDisk()
        gptkStatus = await gptk.detect()
        initialized = true
    }

    func openBottlesFolder() {
        NSWorkspace.shared.open(BottleManager.rootURL)
    }

    func revealWineBinary() {
        if let url = gptk.wineBinaryURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
