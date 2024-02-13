import SwiftUI

struct ImportWalletView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var vaultText = ""

    var body: some View {
        GeometryReader { geometry in
            VStack {
                NavigationStack {
                    VStack(alignment: .leading) {
                        Spacer().frame(height: 30)
                        
                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: $vaultText)
                                .font(.custom("AmericanTypewriter", fixedSize: geometry.size.width * 0.05))
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
                    .navigationTitle("IMPORT")
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
                            Button(action: {}) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.black)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
}

// Preview
struct ImportWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ImportWalletView(presentationStack: .constant([]))
    }
}
