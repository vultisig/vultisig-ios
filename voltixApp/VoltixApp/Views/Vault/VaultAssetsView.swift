//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    //var body: some View {
    //    Text("VaultAssetsView")
    //    List(AssetType.allCases, id: \.self) { asset in
    //       Button(asset.chainName) {
    //           presentationStack.append(.vaultDetailAsset(asset))
    //        }
    //   }
    //}
    
    var body: some View {
            VStack(alignment: .leading) {
              HeaderView(
                rightIcon: "Refresh",
                leftIcon: "Menu",
                head: "VAULT",
                leftAction: {},
                rightAction: {}
              )
              VaultItem(
                coinName: "Bitcoin",
                amount: "1.234",
                isAmount: true,
                numberofAssets: "3",
                coinAmount: "65,899",
                address: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w",
                isRadio: true,
                radioIcon: "largecircle.fill.circle"
              )
              VaultItem(
                coinName: "Ethereum",
                amount: "12,000.12",
                isAmount: false,
                numberofAssets: "3",
                coinAmount: "65,899",
                address: "0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4",
                isRadio: false,
                radioIcon: "largecircle.fill.circle"
              )
              VaultItem(
                coinName: "Solana",
                amount: "12,000.12",
                isAmount: false,
                numberofAssets: "3",
                coinAmount: "65,899",
                address: "ELPecyZbKieSzNUnAGPZma6q7r8DYa7vFapDto7K1GMJ",
                isRadio: false,
                radioIcon: "largecircle.fill.circle"
              )
              VaultItem(
                coinName: "THORChain",
                amount: "12,000.12",
                isAmount: true,
                numberofAssets: "3",
                coinAmount: "65,899",
                address: "thor1cfelrennd7pcvqq7v6w7682v6nhx2uwfg",
                isRadio: true,
                radioIcon: "largecircle.fill.circle"
              )
              Choose(content: "CHAINS")
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
}

#Preview {
    VaultAssetsView(presentationStack: .constant([]))
}
