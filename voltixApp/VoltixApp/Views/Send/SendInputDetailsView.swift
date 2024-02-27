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
import Combine

class DebounceHelper {
    static let shared = DebounceHelper()
    private var workItem: DispatchWorkItem?
    
    func debounce(delay: TimeInterval = 0.5, action: @escaping () -> Void) {
        workItem?.cancel()
        let task = DispatchWorkItem { action() }
        self.workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
}

private let logger = Logger(subsystem: "send-input-details", category: "transaction")
struct SendInputDetailsView: View {
    
    enum Field: Hashable {
        case toAddress
        case amount
        case amountInUSD
        case memo
        case gas
    }
    
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @StateObject var uxto: UnspentOutputsService = UnspentOutputsService()
    @StateObject var cryptoPrice = CryptoPriceService()
    @ObservedObject var tx: SendTransaction
    @State private var isShowingScanner = false
    @State private var isValidAddress = false
    @State private var formErrorMessages = ""
    @State private var isValidForm = true
    @State private var keyboardOffset: CGFloat = 0
    @State private var amountInUsd: Double = 0.0
    
    @State private var coinBalance: String = "0"
    @State private var balanceUSD: String = "0"
    @State private var walletAddress: String = ""
    @State private var isCollapsed = true
    @State private var isLoading = false
    
    @State private var priceRate = 0.0
    
    @FocusState private var focusedField: Field?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if !isLoading {
                    Group {
                        HStack {
                            Text(tx.coin.ticker.uppercased())
                                .font(Font.custom("Menlo", size: 18).weight(.bold))
                            
                            Spacer()
                            
                            Text(String(uxto.walletData?.balanceInBTC ?? "-1")).font(
                                .system(size: 18))
                        }
                    }.padding(.vertical)
                    Group {
                        VStack(alignment: .leading) {
                            Text("From").font(
                                Font.custom("Menlo", size: 18).weight(.bold)
                            ).padding(.bottom)
                            Text(tx.fromAddress)
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
                        TextField("To Address", text: $tx.toAddress)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.default)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .toAddress)
                            .padding()
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(10)
                            .onChange(of: tx.toAddress) { newValue in
                                DebounceHelper.shared.debounce {
                                    if tx.coin.ticker.uppercased() == "BTC" {
                                        
                                        isValidAddress = BitcoinHelper.validateAddress(newValue)
                                        if !isValidAddress {
                                            print("Invalid Crypto Address")
                                        } else {
                                            print("Valid Crypto Address")
                                        }
                                    } else if tx.coin.ticker.uppercased() == "ETH" {
                                        
                                    }
                                }
                            }
                        
                    }.padding(.bottom)
                    Group {
                        HStack{
                            VStack(alignment: .leading){
                                Text("\(tx.coin.ticker.uppercased()):")
                                    .font(Font.custom("Menlo", size: 18).weight(.bold))
                                
                                HStack {
                                    TextField("Amount", text: Binding<String>(
                                        get: { self.tx.amount },
                                        set: { newValue in
                                            self.tx.amount = newValue
                                            DebounceHelper.shared.debounce {
                                                if let newValueDouble = Double(newValue) {
                                                    let rate = self.priceRate
                                                    let newValueUSD = newValueDouble * rate
                                                    tx.amountInUSD = String(format: "%.2f", newValueUSD == 0 ? "" : newValueUSD)
                                                } else {
                                                    tx.amountInUSD = ""
                                                }
                                            }
                                        }
                                    ))
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.decimalPad)
                                    .textContentType(.oneTimeCode)
                                    .disableAutocorrection(true)
                                    .focused($focusedField, equals: .amount)
                                    .padding()
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(10)
                                }
                            }
                            VStack(alignment: .leading){
                                Text("USD:")
                                    .font(Font.custom("Menlo", size: 18).weight(.bold))
                                
                                HStack {
                                    TextField("USD", text: Binding<String>(
                                        get: { self.tx.amountInUSD },
                                        set: { newValue in
                                            self.tx.amountInUSD = newValue
                                            DebounceHelper.shared.debounce {
                                                if let newValueDouble = Double(newValue) {
                                                    let rate = self.priceRate
                                                    if rate > 0 {
                                                        let newValueBTC = newValueDouble / rate
                                                        if newValueBTC != 0 {
                                                            tx.amount = String(format: "%.8f", newValueBTC)
                                                        } else {
                                                            tx.amount = ""
                                                        }
                                                    } else {
                                                        tx.amount = "" 
                                                    }
                                                } else {
                                                    tx.amount = ""
                                                }
                                            }
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .textContentType(.oneTimeCode)
                                    .disableAutocorrection(true)
                                    .focused($focusedField, equals: .amountInUSD)
                                    .padding()
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(10)
                                    
                                    
                                    Button(action: {
                                        if let walletData = uxto.walletData {
                                            self.tx.amount = walletData.balanceInBTC
                                        } else {
                                            Text("Error to fetch the data")
                                        }
                                    }) {
                                        Text("MAX")
                                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                                            .foregroundColor(Color.primary)
                                    }
                                    
                                }
                            }
                        }
                        
                    }.padding(.bottom)
                    
                    Group {
                        Text("Memo:")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                        TextField("Memo", text: $tx.memo)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.default)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .memo)
                            .padding()
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(10)
                    }.padding(.bottom)
                    
                    Group {
                        Text("Fee:")
                            .font(Font.custom("Menlo", size: 18).weight(.bold))
                        HStack {
                            TextField("Fee", text: $tx.gas)
                                .keyboardType(.decimalPad)
                                .textContentType(.oneTimeCode)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .gas)
                                .padding()
                                .background(Color.gray.opacity(0.5))
                                .cornerRadius(10)
                            Spacer()
                            Text("\($tx.gas.wrappedValue) SATS")
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
                                    self.presentationStack.append(.sendVerifyScreen(tx))
                                }
                            }
                        )
                    }
                }
            }
            .overlay(
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.45))
                            .edgesIgnoringSafeArea(.all)
                    }
                }
            )
            .onAppear {
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
            // Reset validation state at the beginning
        formErrorMessages = ""
        isValidForm = true
        
            // Validate the "To" address
        if !isValidAddress {
            formErrorMessages += "Please enter a valid address. \n"
            logger.log("Invalid address.")
            isValidForm = false
        }
        
        let amount = tx.amountDecimal ?? Double(0)
        let gasFee = tx.gasDecimal ?? Double(0)
        
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
        if let walletBalance = uxto.walletData?.balanceDecimal, totalTransactionCost <= Double(walletBalance) {
                // Transaction cost is within balance
        } else {
            formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
            logger.log("Total transaction cost exceeds wallet balance.")
            isValidForm = false
        }
        
        return isValidForm
    }
    
    
    private func updateState() {
        isLoading = true
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
            
            self.priceRate = priceRateUsd
            
            if tx.coin.chain.name.lowercased() == "bitcoin" {
                self.coinBalance = uxto.walletData?.balanceInBTC ?? "0"
                self.balanceUSD = uxto.walletData?.balanceInUSD(usdPrice: priceRateUsd) ?? "0"
                self.walletAddress = uxto.walletData?.address ?? ""
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
                self.coinBalance = "0"
                self.balanceUSD = "US$ 0,00"
                self.walletAddress = "TO BE IMPLEMENTED"
            }
        }
        isLoading = false
    }
    
    private func fetchBalanceAndAddress(for coin: Coin) async {
            // Implement fetching balance and address for the given coin
    }
    
    private func reloadTransactions() {
        
        Task{
            isLoading = true
            await cryptoPrice.fetchCryptoPrices(for: tx.coin.chain.name.lowercased(), for: "usd")
            if tx.coin.ticker.uppercased() == "BTC" {
                if uxto.walletData == nil {
                    await uxto.fetchUnspentOutputs(for: tx.fromAddress)
                }
            }
            
            DispatchQueue.main.async {
                updateState()
                isLoading = false
            }
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
            case .success(let result):
                let qrCodeResult = result.string
                tx.parseCryptoURI(qrCodeResult)
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
            presentationStack: .constant([]), tx: SendTransaction())
    }
}
