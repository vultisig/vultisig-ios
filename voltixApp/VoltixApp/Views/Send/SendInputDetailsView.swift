import SwiftUI
import WalletCore
import OSLog
import CodeScanner
import UniformTypeIdentifiers
// Assuming CurrentScreen is an enum that you've defined elsewhere
import WalletCore




private let logger = Logger(subsystem: "send-input-details", category: "transaction")
struct SendInputDetailsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @StateObject var unspentOutputsViewModel: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var transactionDetailsViewModel: TransactionDetailsViewModel
    @State private var isShowingScanner = false
    @State private var isValidAddress = true
    
    func isValidHex(_ hex: String) -> Bool {
        let hexPattern = "^0x?[0-9A-Fa-f]+$"
        return hex.range(of: hexPattern, options: .regularExpression) != nil
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("BTC")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        if let walletData = unspentOutputsViewModel.walletData {
                            Text(String(walletData.balanceInBTC))
                                .padding().font(.system(size: geometry.size.width * 0.05))
                                .foregroundColor(.black)
                        } else {
                            Text("Error to fetch the data")
                                .padding()
                        }
                    }
                    .padding()
                    .frame(height: geometry.size.height * 0.07)
                    
                    Group {
                        
                        VStack(alignment: .leading) {
                            HStack{
                                Text("To")
                                    .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                                    .foregroundColor(.black)
                                Text(isValidAddress ? "" : "*")
                                    .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                                    .foregroundColor(.red)
                                Spacer()
                                Button("", systemImage: "camera") {
                                    self.isShowingScanner = true
                                }
                                .sheet(isPresented: self.$isShowingScanner, content: {
                                    CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                                })
                                .padding(.trailing, 8)
                                .buttonStyle(PlainButtonStyle())
                                
                            }
                            TextField("", text: $transactionDetailsViewModel.toAddress)
                                .padding()
                                .background(Color(red: 0.92, green: 0.92, blue: 0.93))
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
                                .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                                .foregroundColor(.black)
                            
                            HStack{
                                TextField("", text: $transactionDetailsViewModel.amount)
                                    .keyboardType(.decimalPad)
                                    .padding()
                                    .background(Color(red: 0.92, green: 0.92, blue: 0.93))
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
                                        .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(10)
                                }
                                
                            }
                            
                        }
                        .frame(height: geometry.size.height * 0.12)
                        
                        
                        
                        inputField(title: "Memo", text: $transactionDetailsViewModel.memo, geometry: geometry)
                        
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    gasField(geometry: geometry).padding(.horizontal)
                    BottomBar(content: "CONTINUE", onClick: {
                        // Update this logic as necessary to navigate to the SendVerifyView
                        // self.presentationStack.append(contentsOf: .sendVerifyScreen(transactionDetailsViewModel))
                        
                        self.presentationStack.append(.sendVerifyScreen(transactionDetailsViewModel))
                    })
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
                        await unspentOutputsViewModel.fetchUnspentOutputs(for: $transactionDetailsViewModel.fromAddress.wrappedValue)
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
    
    private func inputField(title: String, text: Binding<String>, geometry: GeometryProxy, isNumeric: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                .foregroundColor(.black)
            TextField("", text: text)
                .padding()
                .background(Color(red: 0.92, green: 0.92, blue: 0.93))
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
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                .foregroundColor(.black)
            Spacer()
            HStack {
                TextField("", text: $transactionDetailsViewModel.gas)
                    .padding()
                    .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 0)
                    )
                Spacer()
                Text("$4.00")
                    .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .frame(height: geometry.size.height * 0.12)
    }
}

// Preview
struct SendInputDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        SendInputDetailsView(presentationStack: .constant([]), unspentOutputsViewModel: UnspentOutputsService(), transactionDetailsViewModel: TransactionDetailsViewModel())
    }
}
