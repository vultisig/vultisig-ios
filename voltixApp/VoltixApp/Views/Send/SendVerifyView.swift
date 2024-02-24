//
//  VoltixApp
//
//  Created by Enrique Souza Soares
//
import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var tx: SendTransaction
    @StateObject var unspentOutputsService: UnspentOutputsService = .init()
    
    @State private var isChecked1 = false
    @State private var isChecked2 = false
    @State private var isChecked3 = false
    
    private var isValidForm: Bool {
        return isChecked1 && isChecked2 && isChecked3
    }
    
    private func reloadTransactions() {
        if unspentOutputsService.walletData == nil {
            Task {
                await unspentOutputsService.fetchUnspentOutputs(for: tx.fromAddress)
                // await unspentOutputsService.fetchUnspentOutputs(for: "bc1qj9q4nsl3q7z6t36un08j6t7knv5v3cwnnstaxu")
            }
        }
    }
    
    var body: some View {
        VStack {
            Form { // Define spacing if needed
                LabelText(title: "FROM", value: tx.fromAddress).padding(.vertical, 10)
                LabelText(title: "TO", value: tx.toAddress).padding(.vertical, 10)
                LabelTextNumeric(title: "AMOUNT", value: tx.amount + " " + tx.coin.ticker).padding(.vertical, 10)
                LabelText(title: "MEMO", value: tx.memo).padding(.vertical, 10)
                LabelTextNumeric(title: "FEE", value: "\(tx.gas) SATS").padding(.vertical, 10)
            }
            
            Group {
                VStack {
                    Toggle("I'M SENDING TO THE RIGHT ADDRESS", isOn: $isChecked1)
                        .toggleStyle(CheckboxToggleStyle())
                    
                    Toggle("THE AMOUNT IS CORRECT", isOn: $isChecked2)
                        .toggleStyle(CheckboxToggleStyle())
                    
                    Toggle("I'M NOT BEING HACKED OR PHISHED", isOn: $isChecked3)
                        .toggleStyle(CheckboxToggleStyle())
                }
                .padding()
            }.padding(.vertical)
            
            Spacer()
            
            Group {
                HStack {
                    Spacer()
                    
                    Text(isValidForm ? "" : "* You must agree with the terms.")
                        .font(Font.custom("Montserrat", size: 13)
                            .weight(.medium))
                        .padding(.vertical, 5)
                        .foregroundColor(.red)
                    BottomBar(
                        content: "SIGN",
                        onClick: {
                            if let walletData = unspentOutputsService.walletData {
                                // Calculate total amount needed by summing the amount and the fee
                                let totalAmountNeeded = tx.amountInSats + tx.feeInSats
                                
                                // Select UTXOs sufficient to cover the total amount needed and map to UtxoInfo
                                let utxoInfo = walletData.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map {
                                    UtxoInfo(
                                        hash: $0.txHash ?? "",
                                        amount: Int64($0.value ?? 0),
                                        index: UInt32($0.txOutputN ?? -1)
                                    )
                                }
                                
                                //                                if utxoInfo.count == 0 {
                                //                                    isValidForm = false
                                //                                    print ("You don't have enough balance to send this transaction")
                                //                                    return
                                //                                }
                                
                                let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
                                
                                //                                // Check if the total selected amount is greater than or equal to the needed balance
                                //                                if totalSelectedAmount < Int64(totalAmountNeeded) {
                                //                                    print("You don't have enough balance to send this transaction")
                                //                                    return
                                //                                }
                                
                                let keysignPayload = KeysignPayload(
                                    coin: tx.coin,
                                    toAddress: tx.toAddress,
                                    toAmount: tx.amountInSats,
                                    byteFee: tx.feeInSats,
                                    utxos: utxoInfo,
                                    memo: tx.memo
                                )
                                
                                self.presentationStack.append(.KeysignDiscovery(keysignPayload))
                                
                            } else {
                                Text("Error fetching the data")
                                    .padding()
                            }
                        }
                    )
                }
//                .onAppear {
//                    reloadTransactions()
//                }
            }
        }
        .navigationTitle("VERIFY")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
    }
    
    // Helper view for label and value text
    @ViewBuilder
    private func LabelText(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Text(value)
                .font(Font.custom("Montserrat", size: 13).weight(.medium))
                .padding(.vertical, 5)
        }
    }
    
    // Helper view for label and value text
    @ViewBuilder
    private func LabelTextNumeric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Spacer()
            Text(value)
                .font(Font.custom("Menlo", size: 30).weight(.ultraLight))
                .padding(.vertical, 5)
            Spacer()
        }
    }
}

// Custom ToggleStyle for Checkbox appearance
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        return HStack {
            Spacer()
            configuration.label
            Image(systemName: configuration.isOn ? "circle.dashed.inset.filled" : "circle.dashed")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(configuration.isOn ? Color.primary : Color.secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

struct SendVerifyView_Previews: PreviewProvider {
    static var previews: some View {
        SendVerifyView(presentationStack: .constant([]), tx: SendTransaction(toAddress: "3JK2dFmWA58A3kukgw1yybotStGAFaV6Sg", amount: "100", memo: "Test Memo", gas: "0.01"))
    }
}
