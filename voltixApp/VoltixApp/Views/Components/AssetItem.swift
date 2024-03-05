    //
    //  NetItem.swift
    //  VoltixApp
    //
    //  Created by Mac on 05.02.2024.
    //

import SwiftUI

struct AssetItem: View {
    let coinName: String;
    let amount:String;
    let usdAmount: String;
    let sendClick: () -> Void;
    let swapClick: () -> Void;
    @State private var fontsize:CGFloat = Utils.isIOS() ? 15 : 40
    var body: some View {
        HStack() {
            Text(coinName)
                .font(.dynamicMenlo(fontsize))
            ;
            Spacer()
            Text(amount)
                .font(.dynamicMenlo(fontsize))
            Spacer()
            Text(usdAmount)
                .font(.dynamicMenlo(fontsize))
            ;
            Spacer()
            VStack{
                Button(action: sendClick) {
                    Text("SEND")
                        .font(.body20MenloBold)
                    
                }.buttonStyle(PlainButtonStyle())
                Button(action: {}) {
                    Text("SWAP")
                        .font(.body20MenloBold)
                    
                }.buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    AssetItem(
        coinName: "Ethereum",
        amount: "23.20980880",
        usdAmount: "US$ 6,660,899,099",
        sendClick: {},
        swapClick: {}
    )
}
