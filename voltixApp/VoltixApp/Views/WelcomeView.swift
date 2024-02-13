import SwiftUI

struct WelcomeView: View {
    @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center) {
                
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
                    
                    BottomBar(
                        content: "START",
                        onClick: {
                            self.presentationStack.append(.startScreen)
                        }
                    )
                    .padding(.bottom, geometry.size.height * 0.02)
                }.onAppear {
                    
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
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
                .navigationTitle("VOLTIX")
                
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
    // Use a computed property to determine if the device is an iPad
    private var isIpad: Bool {
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
#else
        return false
#endif
        
    }
    
    private func featureText(_ text: String, geometry: GeometryProxy) -> some View {
        Text(text)
            .font(.system(size: geometry.size.width * (isIpad ? 0.03 : 0.045), weight: .medium))
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
