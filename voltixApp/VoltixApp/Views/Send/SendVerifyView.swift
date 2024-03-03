    //
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares
    //
import SwiftUI
import BigInt

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var tx: SendTransaction
    @StateObject private var web3Service = Web3Service()
    @StateObject var unspentOutputsService: UnspentOutputsService = .init()
    @State private var errorMessage: String = ""
    @State private var isChecked1 = false
    @State private var isChecked2 = false
    @State private var isChecked3 = false
    
    private var isValidForm: Bool {
        return isChecked1 && isChecked2 && isChecked3
    }
    
    private func reloadTransactions() {
        if tx.coin.chain.name.lowercased() == "bitcoin" {
            if unspentOutputsService.walletData == nil {
                Task {
                    await unspentOutputsService.fetchUnspentOutputs(for: tx.fromAddress)
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            Form {
                LabelText(title: "FROM", value: tx.fromAddress).padding(.vertical, 10)
                LabelText(title: "TO", value: tx.toAddress).padding(.vertical, 10)
                LabelTextNumeric(title: "AMOUNT", value: tx.amount + " " + tx.coin.ticker).padding(.vertical, 10)
                LabelText(title: "MEMO", value: tx.memo).padding(.vertical, 10)
                LabelTextNumeric(title: "FEE", value: "\(tx.gas) \(tx.coin.feeUnit)").padding(.vertical, 10)
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
                    
                    Text(errorMessage)
                        .font(Font.custom("Montserrat", size: 13)
                            .weight(.medium))
                        .padding(.vertical, 5)
                        .foregroundColor(.red)
                    BottomBar(
                        content: "SIGN",
                        onClick: {
                            
                            Task{
                                
                                
                                if !isValidForm {
                                    self.errorMessage = "* You must agree with the terms."
                                    return
                                }
                                
                                if tx.coin.chain.name.lowercased() == "bitcoin" {
                                    
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
                                        
                                        if utxoInfo.count == 0 {
                                            self.errorMessage = "You don't have enough balance to send this transaction"
                                            return
                                        }
                                        
                                        let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
                                        
                                            // Check if the total selected amount is greater than or equal to the needed balance
                                        if totalSelectedAmount < Int64(totalAmountNeeded) {
                                            self.errorMessage = "You don't have enough balance to send this transaction"
                                            return
                                        }
                                        
                                        let keysignPayload = KeysignPayload(
                                            coin: tx.coin,
                                            toAddress: tx.toAddress,
                                            toAmount: tx.amountInSats,
                                            chainSpecific: BlockChainSpecific.Bitcoin(byteFee: tx.feeInSats),
                                            utxos: utxoInfo,
                                            memo: tx.memo
                                        )
                                        
                                        self.errorMessage = ""
                                        self.presentationStack.append(.KeysignDiscovery(keysignPayload))
                                        
                                    } else {
                                        self.errorMessage = "Error fetching the data"
                                    }
                                    
                                } else if tx.coin.chain.name.lowercased() == "ethereum" {
                                    
                                    if tx.coin.contractAddress.isEmpty {
                                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                                            coin: tx.coin,
                                            toAddress: tx.toAddress,
                                            toAmount: tx.amountInGwei, // in Gwei
                                            chainSpecific: BlockChainSpecific.Ethereum(maxFeePerGasGwei: Int64(tx.gas) ?? 24, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: 21_000),
                                            utxos: [],
                                            memo: nil)))
                                    } else {
                                        
                                        let estimatedGas = Int64(await estimateGasForERC20Transfer())
                                        
                                        guard estimatedGas > 0 else {
                                            errorMessage = "Error to estimate gas"
                                            return
                                        }
                                        
                                        print("coin: \(tx.coin.ticker.uppercased()) \n toAddress: \(tx.toAddress) \n toAmount: \(tx.amountInTokenWei) \n fee: \(Int64(tx.gas) ?? 42)")
                                        
                                        
                                        let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
                                        
                                        let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
                                        
                                        let amountToSend = Int64(amountInSmallestUnit)
                                        
                                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                                            coin: tx.coin,
                                            toAddress: tx.toAddress,
                                            toAmount: amountToSend, // The amount must be in the token decimals
                                            chainSpecific: BlockChainSpecific.ERC20(maxFeePerGasGwei: Int64(tx.gas) ?? 42, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: Int64(estimatedGas), contractAddr: tx.coin.contractAddress),
                                            utxos: [],
                                            memo: nil)))
                                    }
                                    
                                }
                                
                                
                            }
                        }
                        
                    )
                }
                .onAppear {
                    reloadTransactions()
                }
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
    
    
    private func estimateGasForERC20Transfer() async -> BigInt {
        
        let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
        
        let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
        
        let value = BigInt(amountInSmallestUnit)
        
        do {
            let estimatedGas = try await web3Service.estimateGasForERC20Transfer(senderAddress: tx.fromAddress, contractAddress: tx.coin.contractAddress, recipientAddress: tx.toAddress, value: value)
            
                // Proceed with transaction signing logic using estimatedGas.
            print("Estimated gas: \(estimatedGas)")
            
            return estimatedGas
        } catch {
            errorMessage = "Error estimating gas: \(error.localizedDescription)"
        }
        return 0
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

