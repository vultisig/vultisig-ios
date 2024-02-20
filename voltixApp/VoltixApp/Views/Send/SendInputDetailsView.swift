import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
// Assuming CurrentScreen is an enum that you've defined elsewhere
import WalletCore

private let logger = Logger(subsystem: "send-input-details", category: "transaction")
struct SendInputDetailsView: View {
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @StateObject var unspentOutputsViewModel: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var transactionDetailsViewModel: SendTransaction
    @State private var isShowingScanner = false
    @State private var isValidAddress = true
    @State private var keyboardOffset: CGFloat = 0
    
    func isValidHex(_ hex: String) -> Bool {
        let hexPattern = "^0x?[0-9A-Fa-f]+$"
        return hex.range(of: hexPattern, options: .regularExpression) != nil
    }
    
    var body: some View {
        ScrollView{
            VStack(alignment: .leading) {
                Group{
                    HStack {
                        Text("BTC")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                        
                        Spacer()
                        
                        if let walletData = unspentOutputsViewModel.walletData {
                            Text(String(walletData.balanceInBTC)).font(.system(size: 18))
                        } else {
                            Text("Error to fetch the data")
                        }
                    }
                }.padding(.vertical)
                Group{
                    VStack(alignment: .leading) {
                        Text("From").font(
                            Font.custom("Menlo", size: 18).weight(.bold)).padding(.bottom)
                        Text($transactionDetailsViewModel.fromAddress.wrappedValue)
                    }
                    
                }.padding(.vertical)
                Group{
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
                        .sheet(
                            isPresented: self.$isShowingScanner,
                            content: {
                                CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                            }
                        )
                    }
                    TextField("", text: $transactionDetailsViewModel.toAddress)
                        .padding()
                        .background(Color.gray.opacity(0.5))  // 50% transparent gray
                        .cornerRadius(10)
                        .onChange(of: transactionDetailsViewModel.toAddress) { newValue in
                            
                            isValidAddress = TWBitcoinAddressIsValidString(newValue) || isValidHex(newValue)
                            if !isValidAddress {
                                print("Invalid Crypto Address")
                            } else {
                                print("Valid Crypto Address")
                            }
                        }
                    
                }.padding(.bottom)
                Group{
                    Text("Amount:")
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    
                    HStack {
                        TextField("", text: $transactionDetailsViewModel.amount)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.gray.opacity(0.5))  // 50% transparent gray
                            .cornerRadius(10)
                        //                    .overlay(
                        //                        RoundedRectangle(cornerRadius: 10)
                        //                            .stroke(Color.gray, lineWidth: 0)
                        //                    )
                        Button(action: {
                            if let walletData = unspentOutputsViewModel.walletData {
                                self.transactionDetailsViewModel.amount = walletData.balanceInBTC
                            } else {
                                Text("Error to fetch the data")
                                    .padding()
                            }
                        }) {
                            Text("MAX")
                                .font(Font.custom("Menlo", size: 18).weight(.bold))
                                .foregroundColor(Color(UIColor.systemFill))
                        }
                        
                    }
                }.padding(.bottom)
                
                Group{
                    Text("Memo:")
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    TextField("", text: $transactionDetailsViewModel.memo)
                        .padding()
                        .background(Color.gray.opacity(0.5))  // 50% transparent gray
                        .cornerRadius(10)
                    //.frame(width: isNumeric ? 280 : nil)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray, lineWidth: 0)
                        )
                }.padding(.bottom)
                
                Group{
                    Text("Fee:")
                    
                        .font(Font.custom("Menlo", size: 18).weight(.bold))
                    HStack {
                        TextField("", text: $transactionDetailsViewModel.gas)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.gray.opacity(0.5))  // 50% transparent gray
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 0)
                            )
                        Spacer()
                        Text($transactionDetailsViewModel.gas.wrappedValue)
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                    }
                }.padding(.bottom)
                Group{
                    BottomBar(
                        content: "CONTINUE",
                        onClick: {
                            // Update this logic as necessary to navigate to the SendVerifyView
                            // self.presentationStack.append(contentsOf: .sendVerifyScreen(transactionDetailsViewModel))
                            
                            self.presentationStack.append(.sendVerifyScreen(transactionDetailsViewModel))
                        }
                    )
                }
            }
            .onAppear {
                if unspentOutputsViewModel.walletData == nil {
                    
                    Task {
                        
                        transactionDetailsViewModel.fromAddress =
                        appState.currentVault?.legacyBitcoinAddress ?? ""
                        if !transactionDetailsViewModel.fromAddress.isEmpty {
                            await unspentOutputsViewModel.fetchUnspentOutputs(
                                for: transactionDetailsViewModel.fromAddress)
                            //await cryptoPriceViewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
                        }
                        
                        //await unspentOutputsViewModel.fetchUnspentOutputs(for: transactionDetailsViewModel.fromAddress)
                    }
                }
            }
            .navigationBarBackButtonHidden()
            .navigationTitle("SEND")
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }.padding()
        
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            transactionDetailsViewModel.parseCryptoURI(qrCodeResult)
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
            presentationStack: .constant([]), unspentOutputsViewModel: UnspentOutputsService(),
            transactionDetailsViewModel: SendTransaction())
    }
}
