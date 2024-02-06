//
//  VaultItem.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct VaultItem: View {
    let coinName: String;
    let amount: String;
    let isAmount: Bool;
    let numberofAssets: String;
    let coinAmount: String;
    let address: String;
    let isRadio: Bool;
    let radioIcon: String;
    var body: some View {
        VStack(alignment: .leading) {
            HStack() {
                Text(coinName)
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    .foregroundColor(.black)
                Spacer()
                if isAmount {
                    Text(amount)
                        .font(Font.custom("Menlo", size: 20))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.black)
                }
                else {
                    AssetsView(numberOfAssets: numberofAssets)
                }
                Spacer().frame(width: 16)
                Text("$" + coinAmount)
                    .font(Font.custom("Menlo", size: 20))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.black)
            }
            HStack() {
                Text(address)
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .lineSpacing(19.50)
                    .foregroundColor(.black);
                Spacer()
                if isRadio {
                    Image(systemName: radioIcon)
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .modifier(ColorInvert())
                }
            }
        }
        .padding()
        .frame(width: .infinity, height: 83)
    }
}

#Preview {
    VaultItem(
            coinName: "THORChain",
            amount: "12,000.12",
            isAmount: true,
            numberofAssets: "3",
            coinAmount: "65899",
            address: "thor1cfelrennd7pcvqq7v6w7682v6nhx2uwfg",
            isRadio: true,
            radioIcon: "largecircle.fill.circle"
    )
}
