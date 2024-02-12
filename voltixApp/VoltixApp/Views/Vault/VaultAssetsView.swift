//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
  @Binding var presentationStack: [CurrentScreen]

  var body: some View {
    VStack(alignment: .leading) {
        LargeHeaderView(
            rightIcon: "Refresh",
            leftIcon: "Menu",
            head: "VAULT",
            leftAction: {},
            rightAction: {},
            back: !Utils.isIOS()
        )
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
        AssetItem(
            coinName: "BTC",
            amount: "1.1",
            usdAmount: "65,899",
            sendClick: {},
            swapClick: {}
        )
    }
    .frame(
        minWidth: 0,
        maxWidth: .infinity,
        minHeight: 0,
        maxHeight: .infinity,
        alignment: .top
    )
  }
}

#Preview {
  VaultAssetsView(presentationStack: .constant([]))
}
