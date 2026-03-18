//
//  KeysignTestView.swift
//  VoltixApp

import SwiftUI

struct KeysignTestView: View {
    @Binding var presentationStack: [CurrentScreen]
    let coin: Coin
    @EnvironmentObject var appState: ApplicationState
    @State private var keysignMessage = "Stuff to sign"
    @State private var currentChain: Chain? = nil
    @State private var toAddress = ""
    @State private var amount = ""
    @State private var feeByte = ""

    var body: some View {
        VStack {
            TextField("ToAddress", text: $toAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            TextField("Amount", text: $amount)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            TextField("fee byte", text: $feeByte)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button("Sign it", systemImage: "person.2.badge.key.fill") {
                guard let toAmt = Float(self.amount) else {
                    print("invalid to amount")
                    return
                }
                let intAmt = Int64(toAmt * 100000000)
                let feeByte = Int64(self.feeByte) ?? 20 // default to 20 sats/vbyte

                let keysignPayload = KeysignPayload(coin: self.coin,
                                                    toAddress: toAddress,
                                                    toAmount: intAmt, byteFee: feeByte,
                                                    utxos: [UtxoInfo(hash: "e9a94b505db829e384c4878171bbf2c60fe685a3450503d65a9d3ae6b1c89777",
                                                                     amount: Int64(398167),
                                                                     index: UInt32(1))])
                self.presentationStack.append(.KeysignDiscovery(keysignPayload))
            }
            Button("join keysign", systemImage: "camera.viewfinder") {
                self.presentationStack.append(.JoinKeysign)
            }
        }
    }
}

#Preview {
    KeysignTestView(presentationStack: .constant([]), coin: Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "", address: ""))
}
