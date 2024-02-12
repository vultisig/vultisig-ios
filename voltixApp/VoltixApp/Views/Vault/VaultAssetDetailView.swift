//
//  VaultAssetDetailView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetDetailView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    let type: AssetType
    
    var body: some View {
        VStack(alignment: .leading) {
          HeaderView(
            rightIcon: "Refresh",
            leftIcon: "BackArrow",
            head: "ETHEREUM",
            leftAction: {},
            rightAction: {}
          )
          VStack(alignment: .leading) {
            HStack() {
                Text("Ethereum")
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    .foregroundColor(.black)
                Spacer().frame(width: 30)
                Button(action: {}) {
                    Image("Copy")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Spacer().frame(width: 40)
                Button(action: {}) {
                    Image("Link")
                        .resizable()
                        .frame(width: 16, height: 20)
                }
                Spacer().frame(width: 40)
                Button(action: {}) {
                    Image("QR")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Spacer()
                Text("$65,899")
                    .font(Font.custom("Menlo", size: 20))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.black)
            }
            Spacer()
            HStack() {
                Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .lineSpacing(19.50)
                    .foregroundColor(.black);
            }
          }
          .frame(width: .infinity, height: 83)
          Choose(content: "TOKENS")
        }
        .padding()
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
    VaultAssetDetailView(presentationStack: .constant([]), type: .bitcoin)
}
