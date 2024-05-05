import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject var viewModel: AccountViewModel
    
    @State var didAppear = false
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack(spacing: 32) {
            Spacer()
            content
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
    
    var content: some View {
        VStack(spacing: 50) {
            VultisigLogo()
            text
        }
    }
    
    var text: some View {
        VStack(spacing: 18) {
            title
            description
        }
    }
    
    var title: some View {
        Text("secureCryptoVault")
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
            .opacity(didAppear ? 1 : 0)
    }
    
    var description: some View {
        Text("homeViewDescription")
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .lineSpacing(10)
            .opacity(didAppear ? 0.8 : 0)
    }
    
    var progress: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }
    
    var tryAgainButton: some View {
        Button {
            viewModel.authenticateUser()
        } label: {
            FilledButton(title: "loginUsingFaceID")
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
            .environmentObject(AccountViewModel())
}
