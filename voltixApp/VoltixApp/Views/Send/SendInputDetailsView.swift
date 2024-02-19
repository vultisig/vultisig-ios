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
        
        GeometryReader { geometry in
            VStack {
                VStack(alignment: .leading) {
                    
                    Text("From").padding(.all).font(
                        Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
                    
                    Text($transactionDetailsViewModel.fromAddress.wrappedValue).padding(.horizontal)
                    HStack {
                        Text("BTC")
                            .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
                        
                        Spacer()
                        
                        if let walletData = unspentOutputsViewModel.walletData {
                            Text(String(walletData.balanceInBTC))
                                .padding().font(.system(size: geometry.size.width * 0.05))
                        } else {
                            Text("Error to fetch the data")
                                .padding()
                        }
                    }
                    .padding()
                    .frame(height: geometry.size.height * 0.07)
                    
                    Group {
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("To")
                                    .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
                                Text(isValidAddress ? "" : "*")
                                    .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
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
                                .padding(.trailing, 8)
                                .buttonStyle(PlainButtonStyle())
                                
                            }
                            TextField("", text: $transactionDetailsViewModel.toAddress)
                                .padding()
                                .background(Color.gray.opacity(0.5))  // 50% transparent gray
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray, lineWidth: 0)
                                )
                                .onChange(of: transactionDetailsViewModel.toAddress) { newValue in
                                    
                                    isValidAddress = TWBitcoinAddressIsValidString(newValue) || isValidHex(newValue)
                                    if !isValidAddress {
                                        print("Invalid Crypto Address")
                                    } else {
                                        print("Valid Crypto Address")
                                    }
                                }
                        }
                        .frame(height: geometry.size.height * 0.12)
                        
                        VStack(alignment: .leading) {
                            Text("Amount")
                                .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
                            
                            HStack {
                                TextField("", text: $transactionDetailsViewModel.amount)
                                    .keyboardType(.decimalPad)
                                    .padding()
                                    .background(Color.gray.opacity(0.5))  // 50% transparent gray
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray, lineWidth: 0)
                                    )
                                Button(action: {
                                    if let walletData = unspentOutputsViewModel.walletData {
                                        self.transactionDetailsViewModel.amount = walletData.balanceInBTC
                                    } else {
                                        Text("Error to fetch the data")
                                            .padding()
                                    }
                                }) {
                                    Text("MAX")
                                        .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
                                        .foregroundColor(Color(UIColor.systemFill))
                                        .padding(10)
                                }
                                
                            }
                            
                        }
                        .frame(height: geometry.size.height * 0.12)
                        
                        inputField(title: "Memo", text: $transactionDetailsViewModel.memo, geometry: geometry)
                        gasField(geometry: geometry)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    BottomBar(
                        content: "CONTINUE",
                        onClick: {
                            // Update this logic as necessary to navigate to the SendVerifyView
                            // self.presentationStack.append(contentsOf: .sendVerifyScreen(transactionDetailsViewModel))
                            
                            self.presentationStack.append(.sendVerifyScreen(transactionDetailsViewModel))
                        }
                    )
                    .padding(.horizontal)
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
            }.onAppear {
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
        }
        
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
    
    private func inputField(
        title: String, text: Binding<String>, geometry: GeometryProxy, isNumeric: Bool = false
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
            TextField("", text: text)
                .padding()
                .background(Color.gray.opacity(0.5))  // 50% transparent gray
                .cornerRadius(10)
                .frame(width: isNumeric ? 280 : nil)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 0)
                )
        }
        .frame(height: geometry.size.height * 0.12)
    }
    
    private func gasField(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading) {
            Text("Fee")
                .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
            Spacer()
            HStack {
                TextField("", text: $transactionDetailsViewModel.gas)
                    .padding()
                    .background(Color.gray.opacity(0.5))  // 50% transparent gray
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 0)
                    )
                Spacer()
                Text($transactionDetailsViewModel.gas.wrappedValue)
                    .font(Font.custom("Menlo", size: geometry.size.width * 0.05).weight(.bold))
            }
        }
        .frame(height: geometry.size.height * 0.12)
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
