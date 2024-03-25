import SwiftUI
import SwiftData

struct WelcomeView: View {
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
            content
            progress
        }
    }
    
    var content: some View {
        VStack(spacing: 50) {
            VoltixLogo()
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
    
    private func setData() {
        withAnimation {
            didAppear = true
        }
    }
}

// Preview
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
    }
}
