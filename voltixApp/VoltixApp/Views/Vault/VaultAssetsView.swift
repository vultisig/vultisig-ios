import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState

    var body: some View {
        ScrollView {
            ForEach(appState.currentVault?.coins ?? []) { coin in
                HStack {
                    Text(coin.symbol)
                    Text(coin.address)
                    Image(systemName: "doc.on.doc")
                    Image(systemName: "square.and.arrow.up")
                    Image(systemName: "qrcode")
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal){
                HStack{
                    Text("\(appState.currentVault?.name ?? "")").onTapGesture {
                        presentationStack.append(CurrentScreen.vaultSelection)
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("setting", systemImage: "gearshape") {
                    // go back to menu screen
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("refresh", systemImage: "arrow.clockwise.circle") {
                    // refresh
                }
            }
        }
    }
}

#Preview {
    VaultAssetsView(presentationStack: .constant([]))
}
