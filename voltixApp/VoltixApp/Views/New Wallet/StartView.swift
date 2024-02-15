import OSLog
import SwiftUI

private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct StartView: View {
    @Binding var presentationStack: [CurrentScreen]
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer()
                    // New Vault Button and Text
                    VStack { // Increase spacing to ensure separation
                        LargeButton(
                            content: "NEW",
                            onClick: {
                                self.presentationStack.append(.newWalletInstructions)
                            }
                        )
                        Text("CREATE A NEW VAULT")
                    }

                    Spacer()
                    // Import Vault Button and Text
                    VStack { // Increase spacing to ensure separation
                        LargeButton(
                            content: "IMPORT",
                            onClick: {
                                self.presentationStack.append(.importWallet)
                            }
                        )

                        Text("IMPORT AN EXISTING VAULT")
                    }

                }
            }
            .frame(width: geometry.size.width)
            .navigationTitle("START")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }
    }
}

// Preview
struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView(presentationStack: .constant([]))
    }
}
