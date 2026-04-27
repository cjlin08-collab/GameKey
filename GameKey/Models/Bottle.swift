import Foundation

/// A Wine prefix on disk. One per launcher. We keep one prefix per launcher (rather than one
/// shared prefix) so a botched install on one launcher can't poison the others.
struct Bottle: Identifiable, Codable, Equatable {
    let id: UUID
    let launcher: Launcher
    /// Display name shown in the UI. Defaults to the launcher's display name.
    var name: String
    /// Directory containing `drive_c`, `system.reg`, etc. Used as `WINEPREFIX`.
    var prefixURL: URL
    /// True once the launcher's installer has finished successfully at least once.
    var installed: Bool
    /// Last time the user opened the launcher. Used for sorting recently-used launchers to the top.
    var lastOpened: Date?

    init(launcher: Launcher, prefixURL: URL) {
        self.id = UUID()
        self.launcher = launcher
        self.name = launcher.displayName
        self.prefixURL = prefixURL
        self.installed = false
        self.lastOpened = nil
    }
}
