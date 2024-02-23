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
                .font(Font.custom("Menlo", size: fontsize))
            ;
            Spacer()
            Text(amount)
                .font(Font.custom("Menlo", size: fontsize))
            Spacer()
            Text(usdAmount)
                .font(Font.custom("Menlo", size: fontsize))
            ;
            Spacer()
            VStack{
                Button(action: sendClick) {
                    Text("SEND")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                    
                }.buttonStyle(PlainButtonStyle())
                Button(action: {}) {
                    Text("SWAP")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                    
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
