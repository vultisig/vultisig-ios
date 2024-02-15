import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    
    @Environment(\.modelContext) private var modelContext
    @State private var vaults: [Vault] = []
    private func loadVaults() {
        do {
            let fetchDescriptor = FetchDescriptor<Vault>()
            self.vaults = try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Error fetching vaults: \(error)")
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
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
                                if $vaults.isEmpty || $vaults.count == 0 {
                                    self.presentationStack.append(.startScreen)
                                } else {
                                    self.presentationStack.append(.vaultAssets(TransactionDetailsViewModel()))
                                }
                            }
                        )
                        .padding(.bottom, geometry.size.height * 0.02)
                    }.onAppear {
                        loadVaults()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .modifier(InlineNavigationBarTitleModifier())
                    .toolbar {
                        
                        ToolbarItem(placement: .navigationBarLeading) {
                            NavigationButtons.backButton(presentationStack: $presentationStack)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationButtons.questionMarkButton
                        }
                    }
                    .navigationTitle("VOLTIX")
                }
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden(true)
    }
    
    // Use a computed property to determine if the device is an iPad
    private var isIpad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
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
