import SwiftUI

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var sheetLauncher: Launcher?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            grid
        }
        .navigationTitle("GameKey")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                gptkBadge
            }
        }
        .sheet(item: $sheetLauncher) { launcher in
            InstallProgressView(launcher: launcher)
                .environmentObject(env)
                .frame(minWidth: 540, minHeight: 360)
        }
    }

    private var sidebar: some View {
        List {
            Section("Launchers") {
                ForEach(Launcher.allCases) { launcher in
                    Label(launcher.displayName, systemImage: launcher.iconSymbol)
                }
            }
            Section("Bottles") {
                ForEach(env.bottles.bottles) { bottle in
                    Label(bottle.name, systemImage: "drop.fill")
                        .foregroundStyle(bottle.installed ? .primary : .secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if case .missing = env.gptkStatus {
                    GPTKMissingBanner()
                }
                if env.thermal.level == .serious || env.thermal.level == .critical {
                    ThermalBanner(level: env.thermal.level,
                                  throttleEnabled: env.thermal.throttleWineProcesses) {
                        env.thermal.throttleWineProcesses.toggle()
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(Launcher.allCases) { launcher in
                        LauncherCard(launcher: launcher) {
                            sheetLauncher = launcher
                            // Kick off the install on first tap. If already installed, the sheet
                            // will read the state and offer to launch instead.
                            if env.bottles.bottle(for: launcher).installed == false {
                                env.installer.install(launcher)
                            }
                        }
                        .environmentObject(env)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a launcher").font(.largeTitle.weight(.semibold))
            Text("GameKey installs each launcher into its own Game Porting Toolkit bottle. You sign in normally inside the launcher's own window.")
                .foregroundStyle(.secondary)
        }
    }

    private var gptkBadge: some View {
        Group {
            switch env.gptkStatus {
            case .unknown:
                ProgressView().controlSize(.small)
            case .missing:
                Label("GPTK missing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .found(let version):
                Label(version, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .foundUnknownVersion:
                Label("GPTK ready", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
    }
}

private struct GPTKMissingBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Game Porting Toolkit not detected").font(.headline)
                Text("GameKey needs GPTK's wine64 binary to run launchers. Install GPTK from Apple's developer site, or point GameKey at an existing wine64 in Settings.")
                    .foregroundStyle(.secondary)
                Link("Open Apple's GPTK page", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Shown when the Mac is under thermal pressure. Honest UX: we can't make Wine cool, only suggest
/// remedies and (optionally) lower wine's CPU priority so the rest of the system stays usable.
struct ThermalBanner: View {
    let level: ThermalMonitor.Level
    let throttleEnabled: Bool
    let toggleThrottle: () -> Void

    var tint: Color { level == .critical ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "thermometer.high")
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("Mac is \(level.displayName.lowercased())").font(.headline)
                if let advice = level.advice {
                    Text(advice).foregroundStyle(.secondary).font(.callout)
                }
                Text("There's no software switch that makes running Windows games cool. The fix is reducing what the system has to do — closing other apps, lowering in-game graphics, or pausing the game.")
                    .foregroundStyle(.tertiary).font(.caption)
                Toggle(isOn: Binding(get: { throttleEnabled }, set: { _ in toggleThrottle() })) {
                    Text("Lower Wine's CPU priority while hot (helps other apps stay responsive)")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(16)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
