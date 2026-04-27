import SwiftUI

/// Routes between the paywall and the main UI based on license state. Putting this in its own
/// view (rather than baking the `if` into App.body) lets us hot-swap with a transition.
struct RootView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Group {
            switch env.license.status {
            case .unknown, .validating:
                bootSplash
            case .unlicensed, .invalid:
                PaywallView()
            case .licensed:
                MainView()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: env.license.isLicensed)
        .task {
            // After validation completes, finish the rest of bootstrap that we deferred.
            if env.license.isLicensed && !env.initialized {
                await env.completeBootstrapAfterLicense()
            }
        }
    }

    private var bootSplash: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Checking your license…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
