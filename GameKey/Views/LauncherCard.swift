import SwiftUI

struct LauncherCard: View {
    let launcher: Launcher
    let onPrimaryAction: () -> Void
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let bottle = env.bottles.bottle(for: launcher)
        let phase = env.installer.phase(for: launcher)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: launcher.iconSymbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: launcher.accentHex))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: launcher.accentHex).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                statusPill(installed: bottle.installed, phase: phase)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(launcher.displayName).font(.title3.weight(.semibold))
                Text(launcher.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }

            Spacer(minLength: 0)

            Button(action: onPrimaryAction) {
                Text(buttonTitle(installed: bottle.installed, phase: phase))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(hex: launcher.accentHex))
        }
        .padding(16)
        .frame(minHeight: 200, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }

    private func statusPill(installed: Bool, phase: LauncherInstaller.Phase) -> some View {
        let label: String
        let color: Color
        switch phase {
        case .idle:
            label = installed ? "Installed" : "Not installed"
            color = installed ? .green : .secondary
        case .downloading:
            label = "Downloading"; color = .blue
        case .preparingPrefix:
            label = "Preparing"; color = .blue
        case .runningInstaller:
            label = "Installing"; color = .blue
        case .finalizing:
            label = "Finishing"; color = .blue
        case .done:
            label = "Done"; color = .green
        case .failed:
            label = "Failed"; color = .red
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func buttonTitle(installed: Bool, phase: LauncherInstaller.Phase) -> String {
        if case .downloading = phase { return "Cancel" }
        switch phase {
        case .preparingPrefix, .runningInstaller, .finalizing: return "Working…"
        case .failed: return "Retry"
        default: break
        }
        return installed ? "Open" : "Install"
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
