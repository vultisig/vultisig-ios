import SwiftUI

struct SendDoneView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in // Use GeometryReader for dynamic sizing
                // Allows content to scroll if it exceeds window size
                VStack(alignment: .leading) {
                    
                    VStack(alignment: .leading) {
                        Text("Transaction")
                            .font(.system(size: geometry.size.width * 0.05)) // Dynamic font sizing
                            .foregroundColor(.black)
                        
                        HStack {
                            Text("bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
                                .font(.system(size: geometry.size.width * 0.04)) // Dynamic font sizing
                                .foregroundColor(.black)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Image("Link")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: geometry.size.width * 0.06) // Dynamic sizing for the image
                        }
                    }
                    .padding() // Padding around the VStack
                    
                    Spacer()
                    
                    BottomBar(
                        content: "COMPLETE",
                        onClick: { }
                    )
                    .padding(.horizontal, geometry.size.width * 0.03) // Dynamic padding
                }.navigationTitle("SEND")
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
        //.edgesIgnoringSafeArea(.all) // Extend to the edges of the display
    }   
}

// Preview
struct SendDoneView_Previews: PreviewProvider {
    static var previews: some View {
        SendDoneView(presentationStack: .constant([]))
    }
}
