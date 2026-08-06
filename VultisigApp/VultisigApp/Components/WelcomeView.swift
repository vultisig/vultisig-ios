import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        view
    }

    /// The brand screen with the launch loader over it. The splash is the one
    /// place that animates — it is the only one a user is waiting on rather than
    /// passing through — so it is also the only caller passing `isStatic: false`.
    var view: some View {
        ZStack(alignment: .bottom) {
            VultisigBrandScreen(isStatic: false)
            loader
        }
    }

    var loader: some View {
        ZStack {
            if viewModel.didUserCancelAuthentication {
                tryAgainButton
            } else {
                progress
            }
        }
        .padding(40)
    }

    var progress: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }

    var tryAgainButton: some View {
        PrimaryButton(title: viewModel.authenticationType.rawValue) {
            viewModel.authenticateUser()
        }
        .accessibilityIdentifier(AccessibilityID.Splash.tryAgainButton)
    }
}

// Preview
#Preview {
        WelcomeView()
            .environmentObject(AppViewModel())
}
