import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var customWineBinary: String = UserDefaults.standard.string(forKey: "gptk.customWineBinary") ?? ""

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            gptkTab.tabItem { Label("Game Porting Toolkit", systemImage: "cube.box") }
            licenseTab.tabItem { Label("License", systemImage: "key.fill") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
        .padding(20)
    }

    private var licenseTab: some View {
        Form {
            Section("Status") {
                LabeledContent("State") {
                    switch env.license.status {
                    case .licensed(let email):
                        Text(email.map { "Active — \($0)" } ?? "Active").foregroundStyle(.green)
                    case .unlicensed: Text("No key entered").foregroundStyle(.orange)
                    case .invalid(let reason): Text(reason).foregroundStyle(.red)
                    case .validating: Text("Validating…").foregroundStyle(.secondary)
                    case .unknown: Text("Checking…").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Move to another Mac") {
                Text("Sign out here to free up an activation slot, then sign in on the new Mac with the same key.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Sign out and remove key", role: .destructive) {
                    env.license.sign()
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Bottles") {
                LabeledContent("Bottles folder") {
                    Text(BottleManager.rootURL.path).font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Reveal in Finder") { env.openBottlesFolder() }
            }
            Section("Cache") {
                LabeledContent("Installer cache") {
                    Text(BottleManager.cacheURL.path).font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Clear cached installers") { clearInstallerCache() }
            }
        }
    }

    private var gptkTab: some View {
        Form {
            Section("Detected") {
                LabeledContent("Status") {
                    switch env.gptkStatus {
                    case .unknown: Text("Detecting…").foregroundStyle(.secondary)
                    case .missing: Text("Not found").foregroundStyle(.orange)
                    case .found(let v): Text(v).foregroundStyle(.green)
                    case .foundUnknownVersion: Text("Found").foregroundStyle(.green)
                    }
                }
                if let url = env.gptk.wineBinaryURL {
                    LabeledContent("wine64") {
                        Text(url.path).font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Section("Override") {
                TextField("Custom wine64 path", text: $customWineBinary)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        env.gptk.setCustomBinaryPath(customWineBinary.isEmpty ? nil : customWineBinary)
                        Task { env.gptkStatus = await env.gptk.detect() }
                    }
                    Button("Use Default") {
                        customWineBinary = ""
                        env.gptk.setCustomBinaryPath(nil)
                        Task { env.gptkStatus = await env.gptk.detect() }
                    }
                }
                Text("Point this at any wine64 binary that ships with Apple's Game Porting Toolkit. The Whiskey app's bundled wine64 also works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("GameKey").font(.title.weight(.semibold))
            Text("v0.1.0").foregroundStyle(.secondary)
            Text("Inspired by Whiskey and Heroic. Built on Apple's Game Porting Toolkit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("Project website", destination: URL(string: "https://gamekey.example/")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clearInstallerCache() {
        try? FileManager.default.removeItem(at: BottleManager.cacheURL)
        try? FileManager.default.createDirectory(at: BottleManager.cacheURL, withIntermediateDirectories: true)
    }
}
