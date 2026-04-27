import Foundation

/// Thin wrapper around running `wine64` and `wineserver`. All callers go through here so we
/// only have one place that knows about environment variables, prefix isolation, and how to
/// stream output back to the UI.
struct WineRunner {
    let wineBinary: URL
    let prefixURL: URL
    /// Optional D3DMetal framework path. When set, we inject the env vars GPTK needs to use it.
    let d3dMetalURL: URL?

    /// Run `wine64 <args>` and stream stdout/stderr lines to `onLine` in order.
    /// Returns the process's exit code.
    @discardableResult
    func run(_ arguments: [String],
             additionalEnv: [String: String] = [:],
             onLine: ((String) -> Void)? = nil) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) { () -> Int32 in
            let process = Process()
            process.executableURL = wineBinary
            process.arguments = arguments
            process.environment = makeEnvironment(extra: additionalEnv)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // Stream both pipes line-by-line so the install progress sheet stays responsive.
            let outQueue = DispatchQueue(label: "wine.stdout")
            let errQueue = DispatchQueue(label: "wine.stderr")
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                outQueue.async {
                    text.split(whereSeparator: \.isNewline)
                        .map(String.init)
                        .forEach { onLine?($0) }
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                errQueue.async {
                    text.split(whereSeparator: \.isNewline)
                        .map(String.init)
                        .forEach { onLine?($0) }
                }
            }

            try process.run()
            process.waitUntilExit()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return process.terminationStatus
        }.value
    }

    /// Run `wineserver -k` to terminate any wine processes still running in this prefix.
    /// Useful when the user wants to force-quit a launcher.
    func killServer() async {
        let server = wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: server.path) else { return }
        let process = Process()
        process.executableURL = server
        process.arguments = ["-k"]
        process.environment = makeEnvironment(extra: [:])
        try? process.run()
        process.waitUntilExit()
    }

    private func makeEnvironment(extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixURL.path
        env["WINEARCH"] = "win64"
        // Quiet down wine's default debug noise unless the user has set WINEDEBUG already.
        if env["WINEDEBUG"] == nil {
            env["WINEDEBUG"] = "-all"
        }
        if let d3d = d3dMetalURL {
            // GPTK needs these to route D3D11/D3D12 through Metal.
            env["DYLD_FALLBACK_LIBRARY_PATH"] = [
                d3d.path,
                env["DYLD_FALLBACK_LIBRARY_PATH"] ?? "/usr/lib"
            ].joined(separator: ":")
            env["MTL_HUD_ENABLED"] = env["MTL_HUD_ENABLED"] ?? "0"
            env["WINEMSYNC"] = "1"
        }
        for (k, v) in extra { env[k] = v }
        return env
    }
}
