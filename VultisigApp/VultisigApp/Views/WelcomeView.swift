import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State var didAppear = false

    var body: some View {
        view
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PrimaryBackgroundWithGradient())
        .onAppear {
            setData()
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    var view: some View {
        VStack(spacing: 32) {
            Spacer()
            logo
            Spacer()
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

    var logo: some View {
        VultisigLogo()
            .offset(y: 20)
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

    private func setData() {
        withAnimation {
            didAppear = true
        }
    }
}

// Preview
#Preview {
        WelcomeView()
            .environmentObject(AppViewModel())
}
