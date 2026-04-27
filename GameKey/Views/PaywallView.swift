import SwiftUI

/// First-run paywall. Replaces MainView until the user pastes a valid license key.
struct PaywallView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var key: String = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            // Sales pitch column up top, simple and quiet.
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("GameKey").font(.title2.weight(.semibold))
                    Spacer()
                }
                Text("Enter your license key").font(.title.weight(.semibold))
                Text("You received a key in your purchase email and on the thanks page after checkout. Paste it below to unlock GameKey on this Mac.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)

            // Input row.
            VStack(alignment: .leading, spacing: 8) {
                TextField("GK-XXXX-XXXX-XXXX-XXXX", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isSubmitting)
                    .onSubmit { submit() }

                if case .invalid(let reason) = env.license.status {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                HStack {
                    Spacer()
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Unlock GameKey")
                                .padding(.horizontal, 14)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(key.isEmpty || isSubmitting)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Footer with purchase CTA + recovery.
            VStack(spacing: 6) {
                HStack {
                    Text("Don't have a key yet?")
                        .foregroundStyle(.secondary)
                    Link("Buy GameKey — $60", destination: URL(string: "https://gamekey.example/#pricing")!)
                }
                Link("Lost your key?", destination: URL(string: "https://gamekey.example/thanks.html")!)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 460)
        .onChange(of: env.license.status) { _, newStatus in
            // When validation finishes, drop the spinner.
            if case .validating = newStatus {} else { isSubmitting = false }
        }
    }

    private func submit() {
        guard !key.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task { await env.license.submit(key: key) }
    }
}
