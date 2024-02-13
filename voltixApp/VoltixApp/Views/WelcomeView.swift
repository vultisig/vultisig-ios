import SwiftUI

struct WelcomeView: View {
    @Binding var presentationStack: Array<CurrentScreen>

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center) {
                NavigationStack {
                    VStack {
                        Spacer()
                        
                        Logo(width: geometry.size.width * 0.25, height: geometry.size.width * 0.25)
                            .padding(.top, geometry.size.height * 0.02)
                        
                        Text("SECURE CRYPTO VAULT")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .padding(.top, geometry.size.height * 0.01)
                            .foregroundColor(.black)
                        
                        VStack(spacing: geometry.size.height * 0.01) {
                            featureText("TWO FACTOR AUTHENTICATION", geometry: geometry)
                            featureText("SECURE, TRUSTED DEVICES", geometry: geometry)
                            featureText("FULLY SELF-CUSTODIAL", geometry: geometry)
                            featureText("NO TRACKING, NO REGISTRATION", geometry: geometry)
                            featureText("FULLY OPEN-SOURCE", geometry: geometry)
                            featureText("AUDITED", geometry: geometry)
                        }
                        .padding(.top, geometry.size.height * 0.02)
                        
                        Spacer()
                        
                        BottomBar(content: "START", onClick: {
                            self.presentationStack.append(.startScreen)
                        })
                        .padding(.bottom, geometry.size.height * 0.02)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
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
                    }
                    .navigationTitle("VOLTIX")
                }
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
    
    private func featureText(_ text: String, geometry: GeometryProxy) -> some View {
        Text(text)
            .font(.system(size: geometry.size.width * (UIDevice.current.userInterfaceIdiom == .pad ? 0.03 : 0.045), weight: .medium))
            .foregroundColor(.black)
            .padding(.horizontal)
    }
}

// Preview
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(presentationStack: .constant([]))
    }
}
