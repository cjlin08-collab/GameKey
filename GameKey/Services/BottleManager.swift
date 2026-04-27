import Foundation

/// Owns the on-disk bottles. Each bottle is a Wine prefix at a known path. We persist a JSON
/// index alongside the bottles so we can show the launcher list before walking the disk.
@MainActor
final class BottleManager: ObservableObject {
    static let rootURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("GameKey/Bottles", isDirectory: true)
    }()

    static let cacheURL: URL = {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cache.appendingPathComponent("GameKey/Installers", isDirectory: true)
    }()

    private static let indexURL = rootURL.appendingPathComponent("bottles.json")

    @Published private(set) var bottles: [Bottle] = []

    func loadFromDisk() async {
        try? FileManager.default.createDirectory(at: Self.rootURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.cacheURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: Self.indexURL),
              let stored = try? JSONDecoder().decode([Bottle].self, from: data) else {
            bottles = []
            return
        }
        bottles = stored
    }

    /// Return the existing bottle for a launcher or create a fresh one (without initializing
    /// the prefix yet — that happens in LauncherInstaller).
    func bottle(for launcher: Launcher) -> Bottle {
        if let existing = bottles.first(where: { $0.launcher == launcher }) {
            return existing
        }
        let prefix = Self.rootURL.appendingPathComponent(launcher.rawValue, isDirectory: true)
        let bottle = Bottle(launcher: launcher, prefixURL: prefix)
        bottles.append(bottle)
        save()
        return bottle
    }

    func update(_ bottle: Bottle) {
        if let idx = bottles.firstIndex(where: { $0.id == bottle.id }) {
            bottles[idx] = bottle
        } else {
            bottles.append(bottle)
        }
        save()
    }

    func delete(_ bottle: Bottle) throws {
        try FileManager.default.removeItem(at: bottle.prefixURL)
        bottles.removeAll { $0.id == bottle.id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bottles)
            try data.write(to: Self.indexURL, options: .atomic)
        } catch {
            // Index is recoverable from disk scan, so log and continue.
            NSLog("GameKey: failed to write bottle index: \(error)")
        }
    }

    /// Set up the basics inside a fresh prefix: run `wineboot --init` so wine creates drive_c,
    /// then apply any preInstall tweaks from the recipe.
    func initializePrefix(_ bottle: Bottle, runner: WineRunner, tweaks: [PrefixTweak]) async throws {
        try FileManager.default.createDirectory(at: bottle.prefixURL, withIntermediateDirectories: true)
        _ = try await runner.run(["wineboot", "--init"])
        for tweak in tweaks {
            try await applyTweak(tweak, runner: runner)
        }
    }

    private func applyTweak(_ tweak: PrefixTweak, runner: WineRunner) async throws {
        switch tweak {
        case .setWindowsVersion(let version):
            // Map e.g. "win10" to the registry value wine expects.
            let key = "HKEY_CURRENT_USER\\Software\\Wine"
            _ = try await runner.run(["reg", "add", key, "/v", "Version", "/d", version, "/f"])
        case .overrideDLL(let name, let mode):
            let key = "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides"
            _ = try await runner.run(["reg", "add", key, "/v", name, "/d", mode, "/f"])
        case .env:
            // Env tweaks are applied at run time by WineRunner, not stored in the prefix.
            break
        }
    }

    /// Collect env vars from a tweak list. WineRunner consumes these per-call.
    static func envOverrides(from tweaks: [PrefixTweak]) -> [String: String] {
        var out: [String: String] = [:]
        for case .env(let key, let value) in tweaks {
            out[key] = value
        }
        return out
    }
}
