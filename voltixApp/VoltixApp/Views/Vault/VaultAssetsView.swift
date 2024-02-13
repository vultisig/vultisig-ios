import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Define the action for menu button
                    }) {
                        Image(systemName: "line.horizontal.3")
                            .foregroundColor(.black) // Customize as needed
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Define the action for refresh button
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.black) // Customize as needed
                    }
                }
            }
        }
        .background(Color.white)
    }
}

#Preview {
    VaultAssetsView(presentationStack: .constant([]))
}
