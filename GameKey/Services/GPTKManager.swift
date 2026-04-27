import Foundation

/// Locates Apple's Game Porting Toolkit on disk. We do not bundle GPTK because Apple's license
/// requires the user to accept it. Instead we look in the standard locations Whiskey, Heroic,
/// and the GPTK installer itself use, and report whether we found a usable wine64 binary.
@MainActor
final class GPTKManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        case missing
        case found(version: String)
        case foundUnknownVersion
    }

    /// Locations we search, in priority order. The user can override via Settings if they
    /// have wine installed somewhere unusual.
    static let defaultSearchPaths: [String] = [
        "/usr/local/opt/game-porting-toolkit/bin/wine64",
        "/opt/homebrew/opt/game-porting-toolkit/bin/wine64",
        "/Applications/Whisky.app/Contents/SharedSupport/Libraries/Wine/bin/wine64",
        "\(NSHomeDirectory())/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
        "\(NSHomeDirectory())/.gptk/bin/wine64",
        "/usr/local/bin/wine64",
        "/opt/homebrew/bin/wine64"
    ]

    @Published private(set) var wineBinaryURL: URL?
    private var customPath: String? {
        UserDefaults.standard.string(forKey: "gptk.customWineBinary")
    }

    func detect() async -> Status {
        let candidate: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
            let fm = FileManager.default
            // Custom path wins.
            if let custom = UserDefaults.standard.string(forKey: "gptk.customWineBinary"),
               fm.isExecutableFile(atPath: custom) {
                return URL(fileURLWithPath: custom)
            }
            for path in Self.defaultSearchPaths {
                if fm.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
            return nil
        }.value

        await MainActor.run { self.wineBinaryURL = candidate }
        guard let url = candidate else { return .missing }

        // Try `wine64 --version`. GPTK reports something like "wine-7.7 (Staging)" or
        // "wine-8.0 (Apple GPTK 2.0)".
        let version = await readVersion(from: url)
        if let version, !version.isEmpty {
            return .found(version: version)
        }
        return .foundUnknownVersion
    }

    func setCustomBinaryPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: "gptk.customWineBinary")
        } else {
            UserDefaults.standard.removeObject(forKey: "gptk.customWineBinary")
        }
    }

    private func readVersion(from binary: URL) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
    }

    /// URL to the SharedSupport directory next to wine64. Used to set DYLD_FALLBACK_LIBRARY_PATH.
    var libraryDirectoryURL: URL? {
        wineBinaryURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib")
    }

    /// Apple's GPTK ships D3DMetal as a bundle of native macOS libraries that wine loads via
    /// override. The path tends to be next to wine64; expose it so WineRunner can set the
    /// right environment variables.
    var d3dMetalLibraryURL: URL? {
        guard let lib = libraryDirectoryURL else { return nil }
        let candidate = lib.appendingPathComponent("external/D3DMetal.framework")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
