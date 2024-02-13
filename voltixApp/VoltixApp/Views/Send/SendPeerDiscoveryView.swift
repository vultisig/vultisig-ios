import SwiftUI

struct SendPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("VERIFY ALL DETAILS")
                    .font(.title2) // Adjusted for dynamic type
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .padding(.top) // Add padding to space out from the navigation bar
                
                Spacer().frame(height: 80)
                
                RadioButtonGroup(
                    items: [
                        "iPhone 15 Pro, “Matt’s iPhone”, 42",
                        "iPhone 13, “Matt’s iPhone 13”, 13",
                    ],
                    selectedId: "iPhone 15 Pro, “Matt’s iPhone”, 42"
                ) { selected in
                    print("Selected is: \(selected)")
                }
                
                Spacer()
                
                WifiBar() // Assuming WifiBar is a custom view you've defined
                
                BottomBar(
                    content: "CONTINUE",
                    onClick: { }
                )
            }
            .navigationTitle("SEND")
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
    }
}

// Preview
struct SendPeerDiscoveryView_Previews: PreviewProvider {
    static var previews: some View {
        SendPeerDiscoveryView(presentationStack: .constant([]))
    }
}


