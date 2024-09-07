import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject var viewModel: AccountViewModel
    
    @State var didAppear = false
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            view
        }
        .onAppear {
            setData()
        }
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
