import SwiftUI

struct ImportFile: View {
    @Binding var presentationStack: Array<CurrentScreen>

    var body: some View {
        GeometryReader { geometry in // Use GeometryReader for dynamic sizing
            VStack {
                FileItem(
                    icon: "MinusCircle",
                    filename: "voltix-vault-share-jun2024.txt"
                )
                .padding(.horizontal, geometry.size.width * 0.05) // Adjust padding dynamically
                
                Spacer()
                
                BottomBar(content: "CONTINUE", onClick: {
                    self.presentationStack.append(.vaultSelection)
                })
                .padding(.bottom, geometry.size.height * 0.02) // Optionally adjust padding at the bottom
            }
            .navigationTitle("IMPORT FILE")
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
            //.padding([.leading, .trailing], geometry.size.width * 0.05) // Apply horizontal padding
        }
        .background(Color.white).navigationBarBackButtonHidden(true)
    }
}

// Preview
struct ImportFile_Previews: PreviewProvider {
    static var previews: some View {
        ImportFile(presentationStack: .constant([]))
    }
}
