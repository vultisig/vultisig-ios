import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        view
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PrimaryBackgroundWithGradient())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    var view: some View {
        ZStack(alignment: .bottom) {
            VultisigLogoAnimation()
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
    }
}

// Preview
#Preview {
        WelcomeView()
            .environmentObject(AppViewModel())
}
