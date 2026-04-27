import Foundation
import AppKit

/// Watches macOS's thermal pressure indicator and surfaces it to the UI. We can't *make* the Mac
/// run cooler — running Windows games through translation is fundamentally CPU/GPU intensive — but
/// we can be a polite citizen: warn the user when the system is under thermal pressure, suggest
/// they close other apps, and let them ask us to gently throttle wine processes if it gets bad.
@MainActor
final class ThermalMonitor: ObservableObject {
    enum Level: String, Equatable {
        case nominal     // Mac is cool. Everything's fine.
        case fair        // Slight warming. Most users won't notice.
        case serious     // System throttling. Performance dropping.
        case critical    // System is hot. Brownouts likely.

        var displayName: String {
            switch self {
            case .nominal:  return "Cool"
            case .fair:     return "Warm"
            case .serious:  return "Hot — throttling"
            case .critical: return "Very hot"
            }
        }

        var advice: String? {
            switch self {
            case .nominal, .fair:
                return nil
            case .serious:
                return "Your Mac is throttling itself to manage heat. Closing other apps (browsers, especially) will help most. Lowering in-game graphics settings inside the running game also helps a lot."
            case .critical:
                return "Your Mac is very hot. Consider quitting the game for a few minutes. Running Windows games through GPTK is computationally heavy — there's no software switch that fixes this, only reducing the workload."
            }
        }
    }

    @Published private(set) var level: Level = .nominal
    /// True when the user has asked us to renice wine processes for lower CPU priority.
    @Published var throttleWineProcesses: Bool = UserDefaults.standard.bool(forKey: "thermal.throttle")
    {
        didSet { UserDefaults.standard.set(throttleWineProcesses, forKey: "thermal.throttle") }
    }

    private var observer: NSObjectProtocol?

    init() {
        update(from: ProcessInfo.processInfo.thermalState)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.update(from: ProcessInfo.processInfo.thermalState)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func update(from state: ProcessInfo.ThermalState) {
        level = switch state {
        case .nominal:  .nominal
        case .fair:     .fair
        case .serious:  .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// Apply nice(1)-style priority drop to all wine64 / wineserver processes currently running.
    /// This won't make the Mac cooler in any meaningful way — wine still uses the GPU heavily and
    /// GPU work isn't affected by CPU niceness — but it does keep the UI of other apps responsive.
    /// Honest UX: we tell the user this is a small, mostly-cosmetic improvement.
    func reniceWineProcesses() {
        // We can't SIGSTOP/SIGCONT or change priority via NSProcessInfo. Use renice directly.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            // Find any wine64/wineserver and renice them to +10 (low priority). Quietly succeed
            // even if there are no matches.
            "pgrep -x 'wine64|wineserver' | xargs -r renice +10 2>/dev/null || true"
        ]
        try? process.run()
    }
}
