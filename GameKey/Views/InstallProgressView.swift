import SwiftUI

struct InstallProgressView: View {
    let launcher: Launcher
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = env.installer.states[launcher] ?? .init(launcher: launcher)
        let bottle = env.bottles.bottle(for: launcher)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: launcher.iconSymbol)
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading) {
                    Text(launcher.displayName).font(.title2.weight(.semibold))
                    Text(subtitle(for: state.phase, installed: bottle.installed))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }

            phaseView(for: state.phase)

            GroupBox("Install log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if state.log.isEmpty {
                            Text("Waiting for output…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 160)
            }

            HStack {
                Spacer()
                if case .failed = state.phase {
                    Button("Retry") { env.installer.install(launcher) }
                        .keyboardShortcut(.defaultAction)
                } else if case .done = state.phase {
                    Button("Open Launcher") {
                        Task { try? await env.installer.launch(launcher) }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if isRunning(state.phase) {
                    Button("Cancel") { env.installer.cancel(launcher) }
                } else if bottle.installed {
                    Button("Open Launcher") {
                        Task { try? await env.installer.launch(launcher) }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func phaseView(for phase: LauncherInstaller.Phase) -> some View {
        switch phase {
        case .idle:
            ProgressView(value: 0).progressViewStyle(.linear)
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction).progressViewStyle(.linear)
                Text("Downloading installer — \(Int(fraction * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .preparingPrefix:
            ProgressView("Preparing Wine prefix").progressViewStyle(.linear)
        case .runningInstaller:
            ProgressView("Running launcher installer (this may take a few minutes)")
                .progressViewStyle(.linear)
        case .finalizing:
            ProgressView("Finishing up").progressViewStyle(.linear)
        case .done:
            Label("Install finished. You can open the launcher and sign in.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func subtitle(for phase: LauncherInstaller.Phase, installed: Bool) -> String {
        switch phase {
        case .idle: return installed ? "Ready to launch." : "Ready to install."
        case .downloading: return "Fetching the official installer from the vendor's CDN."
        case .preparingPrefix: return "Creating an isolated Wine prefix."
        case .runningInstaller: return "The launcher's own installer is running inside the bottle."
        case .finalizing: return "Wrapping up."
        case .done: return "Sign in inside the launcher's window when it opens."
        case .failed: return "Something went wrong. The log below has details."
        }
    }

    private func isRunning(_ phase: LauncherInstaller.Phase) -> Bool {
        switch phase {
        case .downloading, .preparingPrefix, .runningInstaller, .finalizing: return true
        default: return false
        }
    }
}
