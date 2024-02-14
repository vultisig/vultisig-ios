import SwiftUI

struct ImportQRCode: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        GeometryReader { geometry in
            HStack { // Add an HStack to center content horizontally
                Spacer() // Spacer on the left side
                
                VStack { // Your original VStack
                    Spacer() // Top Spacer for vertical centering
                    Image("Capture")
                        .resizable()
                        .aspectRatio(contentMode: .fit) // This ensures the image keeps its aspect ratio
                        .frame(width: 300, height: 300) // Set your desired frame size
                    Spacer() // Bottom Spacer for vertical centering
                }
                
                Spacer() // Spacer on the right side
            }
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
            .navigationTitle("IMPORT QR CODE")
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
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
}

// Preview
struct ImportQRCode_Previews: PreviewProvider {
    static var previews: some View {
        ImportQRCode(presentationStack: .constant([]))
    }
}
