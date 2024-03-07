import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        ZStack {
            background
            view
        }
        .toolbar(.hidden, for: .navigationBar)
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
        VStack(spacing: 12) {
            logo
            title
            description
        }
    }
    
    var logo: some View {
        Logo()
    }
    
    var title: some View {
        Text("secureCryptoVault")
            .font(.body20MenloBold)
    }
    
    var description: some View {
        Text("homeViewDescription")
            .font(.body18Menlo)
            .multilineTextAlignment(.center)
    }
    
    var button: some View {
        BottomBar(
            content: "START",
            onClick: {
                self.presentationStack.append(.startScreen)
            }
        )
    }
}

// Preview
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(presentationStack: .constant([]))
    }
}
