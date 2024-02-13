import SwiftUI
import OSLog

private let logger = Logger(subsystem: "peers-discory", category: "communication")

struct StartView: View {
    @Binding var presentationStack: Array<CurrentScreen>

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                VStack {
                    Spacer()
                    
                    // New Vault Button and Text
                    VStack(spacing: 70) { // Increase spacing to ensure separation
                        LargeButton(content: "NEW", onClick: {
                            self.presentationStack.append(.newWalletInstructions)
                        })
                        .frame(width: geometry.size.width * 0.8, height: 50) // Specify button dimensions
                        
                        Text("CREATE A NEW VAULT")
                            .font(.system(size: geometry.size.width * 0.045)) // Adjust font size
                            .foregroundColor(.black)
                            .frame(width: geometry.size.width * 0.8) // Ensure text does not exceed button width
                    }
                    
                    Spacer()
                    
                    // Import Vault Button and Text
                    VStack(spacing: 70) { // Increase spacing to ensure separation
                        LargeButton(content: "IMPORT", onClick: {
                            self.presentationStack.append(.importWallet)
                        })
                        .frame(width: geometry.size.width * 0.8, height: 50) // Specify button dimensions
                        
                        Text("IMPORT AN EXISTING VAULT")
                            .font(.system(size: geometry.size.width * 0.045)) // Adjust font size
                            .foregroundColor(.black)
                            .frame(width: geometry.size.width * 0.8) // Ensure text does not exceed button width
                    }
                    
                    Spacer()
                }
                .navigationTitle("START")
                .modifier(InlineNavigationBarTitleModifier())
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationButtons.backButton(presentationStack: $presentationStack)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationButtons.questionMarkButton
                    }
                    #else
                    ToolbarItem {
                        NavigationButtons.backButton(presentationStack: $presentationStack)
                    }
                    ToolbarItem {
                        NavigationButtons.questionMarkButton
                    }
                    #endif
                }
                .padding() // Adjust padding to ensure content is centered and spaced out
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
}

// Preview
struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView(presentationStack: .constant([]))
    }
}
