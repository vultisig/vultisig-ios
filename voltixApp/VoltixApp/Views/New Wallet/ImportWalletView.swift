import SwiftUI

struct ImportWalletView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var vaultText = ""

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                VStack(alignment: .leading) {
                    Spacer().frame(height: 30)
                    
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $vaultText)
                            .font(.custom("AmericanTypewriter", size: geometry.size.width * 0.05))
                            .scrollContentBackground(.hidden)
                            .foregroundColor(.black)
                            .frame(height: geometry.size.height * 0.4)
                            .padding()
                            .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                            .cornerRadius(12)
                        
                        HStack {
                            Button(action: {}) {
                                Image(systemName: "camera")
                            }
                            .padding(.trailing, 8)
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {}) {
                                Image(systemName: "doc.text.viewfinder")
                            }
                            .padding(.all, 20)
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Text("ENTER YOUR PREVIOUSLY CREATED VAULT SHARE")
                        .font(.system(size: geometry.size.width * 0.04, weight: .medium))
                        .padding(.top, 8)
                        .foregroundColor(.black)

                    Spacer()
                    
                    BottomBar(content: "CONTINUE", onClick: {
                        self.presentationStack.append(.newWalletInstructions)
                    })
                    .padding(.bottom)
                }
                .padding([.leading, .trailing], geometry.size.width * 0.05)
                // Conditionally apply navigationBarTitleDisplayMode for non-macOS targets
                .navigationTitle("IMPORT")
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
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
    
}

#Preview {
    ImportWalletView(presentationStack: .constant([]))
}

