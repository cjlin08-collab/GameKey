import Foundation

/// Per-launcher install instructions. Keeping these as data instead of code makes it
/// trivial to update a CDN URL without touching the install pipeline.
struct InstallRecipe {
    let launcher: Launcher
    /// Public CDN URL for the installer. Verified manually before each release.
    let installerURL: URL
    /// File name we save the download as. Extension matters: .exe vs .msi changes how we run it.
    let installerFilename: String
    /// Arguments passed to the installer for an unattended install. Empty array means run interactive.
    /// We deliberately prefer interactive installs for launchers that misbehave with /S so the user
    /// can see what's happening; silent flags are only used where we've verified them.
    let silentArgs: [String]
    /// Path inside the prefix to the installed launcher executable, used to start the launcher.
    /// Relative to `<prefix>/drive_c/`.
    let executableRelativePath: String
    /// Optional registry keys, environment variables, or winetricks verbs to apply before install.
    let preInstall: [PrefixTweak]

    /// Full file URL where we save the installer download.
    func downloadDestination(in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent(installerFilename)
    }
}

enum PrefixTweak {
    /// Run a winetricks-equivalent verb inside the prefix. We implement these as direct registry writes
    /// rather than shelling out to winetricks because we don't want a winetricks dependency.
    case setWindowsVersion(String)         // e.g. "win10"
    case overrideDLL(name: String, mode: String) // e.g. ("dxgi", "native,builtin")
    case env(key: String, value: String)
}

/// Static catalog of install recipes. URLs verified Apr 2026; these point at the public CDNs each
/// vendor uses for their own download buttons. If a vendor changes their URL, update it here and
/// ship a new app version — there's no remote config (yet) on purpose.
enum LauncherCatalog {
    static let recipes: [Launcher: InstallRecipe] = [
        .steam: InstallRecipe(
            launcher: .steam,
            installerURL: URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!,
            installerFilename: "SteamSetup.exe",
            silentArgs: ["/S"],
            executableRelativePath: "Program Files (x86)/Steam/Steam.exe",
            preInstall: [
                .setWindowsVersion("win10")
            ]
        ),
        .epic: InstallRecipe(
            launcher: .epic,
            installerURL: URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!,
            installerFilename: "EpicGamesLauncherInstaller.msi",
            silentArgs: ["/quiet"],
            executableRelativePath: "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
            preInstall: [
                .setWindowsVersion("win10")
            ]
        ),
        .gog: InstallRecipe(
            launcher: .gog,
            installerURL: URL(string: "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe")!,
            installerFilename: "GOG_Galaxy_2.0.exe",
            silentArgs: [],
            executableRelativePath: "Program Files (x86)/GOG Galaxy/GalaxyClient.exe",
            preInstall: [
                .setWindowsVersion("win10")
            ]
        ),
        .ubisoft: InstallRecipe(
            launcher: .ubisoft,
            installerURL: URL(string: "https://ubistatic3-a.akamaihd.net/orbit/launcher_installer/UbisoftConnectInstaller.exe")!,
            installerFilename: "UbisoftConnectInstaller.exe",
            silentArgs: ["/S"],
            executableRelativePath: "Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe",
            preInstall: [
                .setWindowsVersion("win10")
            ]
        ),
        .ea: InstallRecipe(
            launcher: .ea,
            installerURL: URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!,
            installerFilename: "EAappInstaller.exe",
            silentArgs: [],
            executableRelativePath: "Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",
            preInstall: [
                .setWindowsVersion("win10"),
                // EA app refuses to start without a real-looking dxgi. Force builtin which works under D3DMetal.
                .overrideDLL(name: "dxgi", mode: "builtin")
            ]
        ),
        .rockstar: InstallRecipe(
            launcher: .rockstar,
            installerURL: URL(string: "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe")!,
            installerFilename: "Rockstar-Games-Launcher.exe",
            silentArgs: ["/S"],
            executableRelativePath: "Program Files/Rockstar Games/Launcher/LauncherPatcher.exe",
            preInstall: [
                .setWindowsVersion("win10")
            ]
        )
    ]
}
