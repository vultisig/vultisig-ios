//
//  VoltixApp
//
//  Created by Enrique Souza Soares
//
import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore

private let logger = Logger(subsystem: "send-input-details", category: "transaction")
struct SendInputDetailsView: View {
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @StateObject var unspentOutputsService: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var sendTransactionModel: SendTransaction
    @State private var isShowingScanner = false
    @State private var isValidAddress = false
    @State private var formErrorMessages = ""
    @State private var isValidForm = true
    @State private var keyboardOffset: CGFloat = 0
    
    // @State private var keysignMessage = "Stuff to sign"
    // @State private var currentChain: Chain? = nil
    
    func isValidHex(_ hex: String) -> Bool {
        let hexPattern = "^0x?[0-9A-Fa-f]+$"
        return hex.range(of: hexPattern, options: .regularExpression) != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    HStack {
                        Text("BTC")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                        
                        Spacer()
                        
                        Text(String(unspentOutputsService.walletData?.balanceInBTC ?? "-1")).font(
                            .system(size: 18))
                    }
                }.padding(.vertical)
                Group {
                    VStack(alignment: .leading) {
                        Text("From").font(
                            Font.custom("Menlo", size: 18).weight(.bold)
                        ).padding(.bottom)
                        Text(sendTransactionModel.fromAddress)
                    }
                    
                }.padding(.vertical)
                Group {
                    HStack {
                        Text("To:")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                        Text(isValidAddress ? "" : "*")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                            .foregroundColor(.red)
                        Spacer()
                        Button("", systemImage: "camera") {
                            self.isShowingScanner = true
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(
                            isPresented: self.$isShowingScanner,
                            content: {
                                CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                            }
                        )
                    }
                    TextField("", text: $sendTransactionModel.toAddress)
                        .padding()
                        .background(Color.gray.opacity(0.5))  // 50% transparent gray
                        .cornerRadius(10)
                        .onChange(of: sendTransactionModel.toAddress) { newValue in
                            
                            isValidAddress = TWBitcoinAddressIsValidString(newValue) || isValidHex(newValue)
                            if !isValidAddress {
                                print("Invalid Crypto Address")
                            } else {
                                print("Valid Crypto Address")
                            }
                        }
                    
                }.padding(.bottom)
                Group {
                    Text("Amount:")
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    
                    HStack {
                        TextField("", text: $sendTransactionModel.amount)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.gray.opacity(0.5))  // 50% transparent gray
                            .cornerRadius(10)
                        Button(action: {
                            if let walletData = unspentOutputsService.walletData {
                                self.sendTransactionModel.amount = walletData.balanceInBTC
                            } else {
                                Text("Error to fetch the data")
                                    .padding()
                            }
                        }) {
                            Text("MAX")
                                .font(Font.custom("Menlo", size: 18).weight(.bold))
                                .foregroundColor(Color.primary)
                        }
                        
                    }
                }.padding(.bottom)
                
                Group {
                    Text("Memo:")
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    TextField("", text: $sendTransactionModel.memo)
                        .padding()
                        .background(Color.gray.opacity(0.5))  // 50% transparent gray
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray, lineWidth: 0)
                        )
                }.padding(.bottom)
                
                Group {
                    Text("Fee:")
                    
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    HStack {
                        TextField("", text: $sendTransactionModel.gas)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.gray.opacity(0.5))  // 50% transparent gray
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 0)
                            )
                        Spacer()
                        Text($sendTransactionModel.gas.wrappedValue)
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                    }
                }.padding(.bottom)
                Text(isValidForm ? "" : formErrorMessages)
                    .font(Font.custom("Menlo", size: 13).weight(.bold))
                    .foregroundColor(.red)
                    .padding()
                Group {
                    BottomBar(
                        content: "CONTINUE",
                        onClick: {
                            if validateForm() {
                                self.presentationStack.append(.sendVerifyScreen(sendTransactionModel))
                            }
                        }
                    )
                }
            }
            .onAppear {
                print(sendTransactionModel.toString())
                reloadTransactions()
            }
            .navigationBarBackButtonHidden()
            .navigationTitle("SEND")
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.refreshButton(action: {
                        reloadTransactions()
                    })
                }
            }
        }.padding()
        
    }
    
    private func validateForm() -> Bool {
        return true
        // Reset validation state at the beginning
        formErrorMessages = ""
        isValidForm = true
        
        // Validate the "To" address
        if !isValidAddress {
            formErrorMessages += "Please enter a valid address. \n"
            logger.log("Invalid address.")
            isValidForm = false
        }
        
        let amount = sendTransactionModel.amountDecimal ?? Double(0)
        let gasFee = sendTransactionModel.gasDecimal ?? Double(0)
        
        if amount <= 0 {
            formErrorMessages += "Amount must be a positive number. Please correct your entry. \n"
            logger.log("Invalid or non-positive amount.")
            isValidForm = false
            return isValidForm
        }
        
        if gasFee <= 0 {
            formErrorMessages += "Fee must be a non-negative number. Please correct your entry. \n"
            logger.log("Invalid or negative fee.")
            isValidForm = false
            return isValidForm
        }
        
        // Calculate the total transaction cost
        let totalTransactionCost = amount + gasFee
        
        print("Total transaction cost: \(totalTransactionCost)")
        
        // Verify if the wallet balance can cover the total transaction cost
        if let walletBalance = unspentOutputsService.walletData?.balanceDecimal, totalTransactionCost <= Double(walletBalance) {
            // Transaction cost is within balance
        } else {
            formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
            logger.log("Total transaction cost exceeds wallet balance.")
            isValidForm = false
        }
        
        return isValidForm
    }
    
    
    
    
    private func reloadTransactions() {
        if unspentOutputsService.walletData == nil {
            Task {
                await unspentOutputsService.fetchUnspentOutputs(for: sendTransactionModel.fromAddress)
            }
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            sendTransactionModel.parseCryptoURI(qrCodeResult)
            self.isShowingScanner = false
        case .failure(let err):
            logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
}

// Preview
struct SendInputDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        SendInputDetailsView(
            presentationStack: .constant([]), sendTransactionModel: SendTransaction())
    }
}
