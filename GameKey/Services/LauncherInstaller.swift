import Foundation
import Combine

/// Coordinates the full install flow for a launcher: download installer → init prefix → run
/// installer → mark bottle installed. Publishes progress so the UI can show a single sheet
/// from kickoff to completion.
@MainActor
final class LauncherInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case preparingPrefix
        case runningInstaller
        case finalizing
        case done
        case failed(message: String)
    }

    struct State: Equatable {
        var launcher: Launcher
        var phase: Phase = .idle
        var log: [String] = []
    }

    @Published private(set) var states: [Launcher: State] = [:]

    private let bottles: BottleManager
    private let gptk: GPTKManager
    private var inFlight: [Launcher: Task<Void, Never>] = [:]

    init(bottles: BottleManager, gptk: GPTKManager) {
        self.bottles = bottles
        self.gptk = gptk
    }

    func phase(for launcher: Launcher) -> Phase {
        states[launcher]?.phase ?? .idle
    }

    /// Kick off install. If one is already running for this launcher, this is a no-op.
    func install(_ launcher: Launcher) {
        guard inFlight[launcher] == nil else { return }
        states[launcher] = State(launcher: launcher, phase: .downloading(fraction: 0))

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runInstall(launcher: launcher)
                self.update(launcher) { $0.phase = .done }
            } catch {
                self.update(launcher) { state in
                    state.phase = .failed(message: error.localizedDescription)
                    state.log.append("ERROR: \(error.localizedDescription)")
                }
            }
            self.inFlight[launcher] = nil
        }
        inFlight[launcher] = task
    }

    func cancel(_ launcher: Launcher) {
        inFlight[launcher]?.cancel()
        inFlight[launcher] = nil
        update(launcher) { $0.phase = .idle }
    }

    /// Open an already-installed launcher.
    func launch(_ launcher: Launcher) async throws {
        guard let wine = gptk.wineBinaryURL else { throw InstallError.gptkMissing }
        let recipe = try recipeFor(launcher)
        let bottle = bottles.bottle(for: launcher)
        guard bottle.installed else { throw InstallError.notInstalledYet }

        let runner = WineRunner(wineBinary: wine,
                                prefixURL: bottle.prefixURL,
                                d3dMetalURL: gptk.d3dMetalLibraryURL)
        let executable = bottle.prefixURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent(recipe.executableRelativePath)

        // Start the launcher and detach. We don't wait — the launcher may run for hours.
        Task.detached(priority: .userInitiated) {
            let env = BottleManager.envOverrides(from: recipe.preInstall)
            _ = try? await runner.run(["start", "/unix", executable.path], additionalEnv: env)
        }

        var updated = bottle
        updated.lastOpened = Date()
        bottles.update(updated)
    }

    // MARK: - Internal

    private func runInstall(launcher: Launcher) async throws {
        guard let wine = gptk.wineBinaryURL else { throw InstallError.gptkMissing }
        let recipe = try recipeFor(launcher)
        let bottle = bottles.bottle(for: launcher)
        let runner = WineRunner(wineBinary: wine,
                                prefixURL: bottle.prefixURL,
                                d3dMetalURL: gptk.d3dMetalLibraryURL)

        // 1. Download the installer.
        let dest = recipe.downloadDestination(in: BottleManager.cacheURL)
        let downloader = Downloader()
        for try await event in downloader.downloadAsync(from: recipe.installerURL, to: dest) {
            try Task.checkCancellation()
            switch event {
            case .progress(let fraction):
                update(launcher) { $0.phase = .downloading(fraction: fraction) }
            case .completed:
                update(launcher) { $0.log.append("Downloaded installer to \(dest.lastPathComponent)") }
            }
        }

        // 2. Initialize the prefix if needed.
        update(launcher) { $0.phase = .preparingPrefix }
        try await bottles.initializePrefix(bottle, runner: runner, tweaks: recipe.preInstall)

        // 3. Run the installer.
        update(launcher) { $0.phase = .runningInstaller }
        let invocation = installerInvocation(for: recipe, installerPath: dest)
        let env = BottleManager.envOverrides(from: recipe.preInstall)
        let exit = try await runner.run(invocation, additionalEnv: env) { [weak self] line in
            // Runs on background queue. Hop to main to mutate published state.
            Task { @MainActor in
                self?.update(launcher) { $0.log.append(line) }
            }
        }
        guard exit == 0 else {
            throw InstallError.installerFailed(code: exit)
        }

        // 4. Mark installed.
        update(launcher) { $0.phase = .finalizing }
        var updated = bottle
        updated.installed = true
        bottles.update(updated)
    }

    private func installerInvocation(for recipe: InstallRecipe, installerPath: URL) -> [String] {
        // .msi files are run via msiexec; .exe files are run directly.
        if recipe.installerFilename.lowercased().hasSuffix(".msi") {
            return ["msiexec", "/i", installerPath.path] + recipe.silentArgs
        }
        return [installerPath.path] + recipe.silentArgs
    }

    private func recipeFor(_ launcher: Launcher) throws -> InstallRecipe {
        guard let recipe = LauncherCatalog.recipes[launcher] else {
            throw InstallError.unknownLauncher
        }
        return recipe
    }

    private func update(_ launcher: Launcher, _ mutate: (inout State) -> Void) {
        var state = states[launcher] ?? State(launcher: launcher)
        mutate(&state)
        states[launcher] = state
    }

    enum InstallError: LocalizedError {
        case gptkMissing
        case unknownLauncher
        case installerFailed(code: Int32)
        case notInstalledYet

        var errorDescription: String? {
            switch self {
            case .gptkMissing:
                return "Apple Game Porting Toolkit isn't installed. Open Settings → Game Porting Toolkit to set it up."
            case .unknownLauncher:
                return "No install recipe is registered for this launcher."
            case .installerFailed(let code):
                return "The installer exited with status \(code). See the install log for details."
            case .notInstalledYet:
                return "This launcher hasn't been installed yet. Click Install first."
            }
        }
    }
}
