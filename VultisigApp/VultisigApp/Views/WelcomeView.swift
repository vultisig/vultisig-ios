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
        VStack(spacing: 40) {
            VultisigLogo()
            text
        }
        .offset(y: 20)
    }
    
    var text: some View {
        Text("secureCryptoVault")
            .font(.body16MontserratSemiBold)
            .foregroundColor(.neutral0)
            .opacity(didAppear ? 1 : 0)
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
