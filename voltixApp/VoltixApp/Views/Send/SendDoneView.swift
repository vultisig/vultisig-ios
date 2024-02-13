import SwiftUI

struct SendDoneView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        GeometryReader { geometry in // Use GeometryReader for dynamic sizing
             // Allows content to scroll if it exceeds window size
                VStack(alignment: .leading) {
                    HeaderView(
                        rightIcon: "QuestionMark",
                        leftIcon: "BackArrow",
                        head: "SEND",
                        leftAction: {
                            if !self.presentationStack.isEmpty {
                                self.presentationStack.removeLast()
                            }
                        },
                        rightAction: {}
                    )
                    .padding(.horizontal, geometry.size.width * 0.03) // Dynamic padding based on width
                    
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
                }
            }
        }
        //.edgesIgnoringSafeArea(.all) // Extend to the edges of the display
    
}

// Preview
struct SendDoneView_Previews: PreviewProvider {
    static var previews: some View {
        SendDoneView(presentationStack: .constant([]))
    }
}
