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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            if !presentationStack.isEmpty {
                                presentationStack.removeLast()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.black)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            // Define right action here
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.black)
                        }
                    }
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
