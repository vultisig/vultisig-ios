import SwiftUI

struct VaultAssetsView: View {
  @Binding var presentationStack: [CurrentScreen]
  @EnvironmentObject var appState: ApplicationState

  @State private var signingTestView = false
  var body: some View {

    VStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          VaultItem(
            coinName: "Bitcoin",
            amount: "1.1",
            showAmount: false,
            coinAmount: "65,899",
            address: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
            isRadio: false,
            showButtons: true,
            onClick: {}
          )
          .padding()

          AssetItem(
            coinName: "BTC",
            amount: "1.1",
            usdAmount: "65,899",
            sendClick: {},
            swapClick: {}
          )
          .padding()
        }
      }

      BottomBar(
        content: "CONTINUE",
        onClick: {
          // Define the action for continue button
        }
      )
      .padding()
    }
    .navigationTitle("VAULT")
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

    .background(Color.white)
  }
}

#Preview {
  VaultAssetsView(presentationStack: .constant([]))
}
