import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Binding var presentationStack: [CurrentScreen]
    
    @State var didAppear = false
    
    var body: some View {
        ZStack {
            background
            view
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            setData()
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            Spacer()
            content
            Spacer()
            button
        }
    }
    
    var content: some View {
        VStack(spacing: 50) {
            Logo()
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
    
    var button: some View {
        FilledButton(title: "start")
            .padding(40)
            .opacity(didAppear ? 1 : 0)
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
        WelcomeView(presentationStack: .constant([]))
    }
}
