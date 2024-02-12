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
    @State private var fontsize:CGFloat = Utils.isIOS() ? 20 : 40
    var body: some View {
        HStack() {
            Text(coinName)
                .font(Font.custom("Menlo", size: fontsize))
                .lineSpacing(30)
                .frame(width: 250)
                .foregroundColor(.black);
            Text(amount)
                .font(Font.custom("Menlo", size: fontsize))
                .lineSpacing(30)
                .foregroundColor(.black);
            Spacer().frame(width: 16)
            Text("$" + usdAmount)
                .font(Font.custom("Menlo", size: fontsize))
                .lineSpacing(30)
                .foregroundColor(.black);
            Spacer()
            #if os(iOS)
            VStack() {
                Button(action: {}) {
                    Text("SEND")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black);
                }
                Button(action: {}) {
                    Text("SWAP")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black);
                }
                
            }
            .frame(width: 105, height: 70)
            #else
            HStack() {
                Button(action: {}) {
                    Text("SEND")
                        .font(Font.custom("Menlo", size: 40).weight(.bold))
                        .lineSpacing(60)
                        .foregroundColor(.black);
                }
                .frame(width: 180)
                Button(action: {}) {
                    Text("SWAP")
                        .font(Font.custom("Menlo", size: 40).weight(.bold))
                        .lineSpacing(60)
                        .foregroundColor(.black);
                }
                .frame(width: 180)
            }
            .frame(height: 75)
            #endif
        }
        .padding(.leading, 30)
        .frame(height: 100)
    }
}

#Preview {
    AssetItem(
        coinName: "ETH",
        amount: "23.2",
        usdAmount: "60,899",
        sendClick: {},
        swapClick: {}
    )
}
