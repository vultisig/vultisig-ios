    //
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares
    //
    // TODO: Create an abstraction, so we dont keep using if coin...
    // I will do it after the MVP
    //
import CodeScanner
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WalletCore
import Combine
import UIKit
import BigInt

private class DebounceHelper {
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
    @StateObject var eth: EthplorerAPIService = EthplorerAPIService()
    @StateObject var web3Service = Web3Service()
    @StateObject var cryptoPrice = CryptoPriceService.shared
    @ObservedObject var tx: SendTransaction
    @State private var isShowingScanner = false
    @State private var isValidAddress = false
    @State private var formErrorMessages = ""
    @State private var isValidForm = true
    @State private var keyboardOffset: CGFloat = 0
    @State private var amountInUsd: Double = 0.0
    @State private var coinBalance: String = "0"
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
                            
                            Text(coinBalance).font(
                                .system(size: 18))
                        }
                    }.padding(.vertical)
                    Group {
                        VStack(alignment: .leading) {
                            Text("From").font(Font.custom("Menlo", size: 18).weight(.bold)).padding(.bottom)
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
                            Button("", systemImage: "doc.on.clipboard") {
                                if let clipboardContent = UIPasteboard.general.string {
                                    tx.toAddress = clipboardContent
                                        // Trigger the validation logic after pasting
                                    if tx.coin.ticker.uppercased() == "BTC" {
                                        isValidAddress = BitcoinHelper.validateAddress(clipboardContent)
                                    } else if tx.coin.chain.name.lowercased() == "ethereum" {
                                        isValidAddress = CoinType.ethereum.validate(address: clipboardContent)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
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
                        TextField("To Address", text: Binding<String>(
                            get: { self.tx.toAddress },
                            set: { newValue in
                                self.tx.toAddress = newValue
                                DebounceHelper.shared.debounce {
                                        //TODO: move this logic into an abstraction
                                    if tx.coin.ticker.uppercased() == "BTC" {
                                        isValidAddress = BitcoinHelper.validateAddress(newValue)
                                    } else if tx.coin.chain.name.lowercased() == "ethereum" {
                                        isValidAddress = CoinType.ethereum.validate(address: newValue)
                                    }
                                }
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.default)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .toAddress)
                        .padding()
                        .background(Color.gray.opacity(0.5))
                        .cornerRadius(10)
                        
                        
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
                                                    //TODO: move this logic into an abstraction
                                                if let newValueDouble = Double(newValue) {
                                                    if tx.coin.chain.name.lowercased() == "bitcoin" {
                                                        let rate = self.priceRate
                                                        let newValueUSD = newValueDouble * rate
                                                        tx.amountInUSD = String(format: "%.2f", newValueUSD == 0 ? "" : newValueUSD)
                                                    }else if tx.coin.chain.name.lowercased() == "ethereum" {
                                                        if tx.coin.ticker.uppercased() == "ETH" {
                                                            tx.amountInUSD = eth.addressInfo?.ETH.getAmountInUsd(newValueDouble) ?? ""
                                                        } else {
                                                            if let tokenInfo = eth.addressInfo?.tokens?.first(where: {$0.tokenInfo.symbol == "USDC"}) {
                                                                tx.amountInUSD = tokenInfo.getAmountInUsd(newValueDouble)
                                                            }
                                                        }
                                                    }
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
                                                //TODO: move this logic into an abstraction
                                            DebounceHelper.shared.debounce {
                                                if let newValueDouble = Double(newValue) {
                                                    if tx.coin.chain.name.lowercased() == "bitcoin" {
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
                                                    } else if tx.coin.chain.name.lowercased() == "ethereum" {
                                                        if tx.coin.ticker.uppercased() == "ETH" {
                                                            tx.amount = eth.addressInfo?.ETH.getAmountInEth(newValueDouble) ?? ""
                                                        } else {
                                                            if let tokenInfo = eth.addressInfo?.tokens?.first(where: {$0.tokenInfo.symbol == "USDC"}) {
                                                                tx.amount = tokenInfo.getAmountInTokens(newValueDouble)
                                                            }
                                                        }
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
                                            //TODO: move this logic into an abstraction
                                        setMaxValues()
                                        
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
                            Text("\($tx.gas.wrappedValue) \(tx.coin.feeUnit ?? "NO UNIT")")
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
        
        let amount = tx.amountDecimal
        let gasFee = tx.gasDecimal
        
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
        
            // TODO: Move this to an abstraction
            // This is only for MVP
        if tx.coin.chain.name.lowercased() == "bitcoin" {
            let walletBalanceInSats = uxto.walletData?.balance ?? 0
            let totalTransactionCostInSats = tx.amountInSats + tx.feeInSats
            print("Total transaction cost: \(totalTransactionCostInSats)")
            
            if totalTransactionCostInSats > walletBalanceInSats {
                formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
                logger.log("Total transaction cost exceeds wallet balance.")
                isValidForm = false
            }
            
        } else if tx.coin.chain.name.lowercased() == "ethereum" {
            
            let ethBalanceInWei = Int(eth.addressInfo?.ETH.rawBalance ?? "0") ?? 0 // it is in WEI
            
            if tx.coin.ticker.uppercased() == "ETH" {
                
                if tx.totalEthTransactionCostWei > ethBalanceInWei {
                    formErrorMessages += "The combined amount and fee exceed your wallet's balance. Please adjust to proceed. \n"
                    logger.log("Total transaction cost exceeds wallet balance.")
                    isValidForm = false
                }
                
            } else {
                
                if let tokenInfo = eth.addressInfo?.tokens?.first(where: {$0.tokenInfo.symbol == tx.coin.ticker.uppercased()}) {
                    
                    print ("tx.feeInWei \(tx.feeInWei)")
                    print ("ethBalanceInWei \(ethBalanceInWei)")
                    
                    print ("has eth to pay the fee?  \(tx.feeInWei > ethBalanceInWei)")
                    
                    
                    if tx.feeInWei > ethBalanceInWei {
                        formErrorMessages += "You must have ETH in to send any TOKEN, so you can pay the fees. \n"
                        logger.log("You must have ETH in to send any TOKEN, so you can pay the fees. \n")
                        isValidForm = false
                    }
                    
                    let tokenBalance = Int(tokenInfo.rawBalance) ?? 0
                    
                    if tx.amountInTokenWei > tokenBalance {
                        formErrorMessages += "Total transaction cost exceeds wallet balance. \n"
                        logger.log("Total transaction cost exceeds wallet balance.")
                        isValidForm = false
                    }
                    
                }
            }
            
            
            
        }
        
        
        
        return isValidForm
    }
    
    private func setMaxValues() {
        if tx.coin.chain.name.lowercased() == "bitcoin" {
            let rate = self.priceRate
            if let walletData = uxto.walletData {
                self.tx.amount = walletData.balanceInBTC
                self.tx.amountInUSD = String(format: "%.2f", walletData.balanceDecimal * rate)
            }
        } else if tx.coin.chain.name.lowercased() == "ethereum" {
            if tx.coin.ticker.uppercased() == "ETH" {
                self.tx.amount = eth.addressInfo?.ETH.balanceString ?? "0.0"
                self.tx.amountInUSD = eth.addressInfo?.ETH.balanceInUsd.replacingOccurrences(of: "US$ ", with: "") ?? ""
            } else {
                if let tokenInfo = eth.addressInfo?.tokens?.first(where: { $0.tokenInfo.symbol == "USDC" }) {
                    self.tx.amount = tokenInfo.balanceString
                    self.tx.amountInUSD = tokenInfo.balanceInUsd.replacingOccurrences(of: "US$ ", with: "")
                }
            }
        }
    }
    
    private func updateState() {
        isLoading = true
            //TODO: move this logic into an abstraction
        if tx.coin.chain.name.lowercased() == "bitcoin" {
            if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
                self.priceRate = priceRateUsd
                self.coinBalance = uxto.walletData?.balanceInBTC ?? "0"
            }
        } else if tx.coin.chain.name.lowercased() == "ethereum" {
                // We need to pass it to the next view
            tx.eth = eth.addressInfo
            
            let gasPriceInGwei = BigInt(web3Service.gasPrice ?? 0) / BigInt(10).power(9)
            
            print("Gas price in Gwei: \(gasPriceInGwei)")
            
            tx.gas = String(gasPriceInGwei)
            tx.nonce = Int64(web3Service.nonce ?? 0)
            
            if tx.token != nil {
                self.coinBalance = tx.token?.balanceString ?? ""
            } else {
                self.coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
            }
        }
        isLoading = false
    }
    
    private func reloadTransactions() {
            //TODO: move this logic into an abstraction
        Task {
            isLoading = true
            if tx.coin.chain.name.lowercased() == "bitcoin" {
                await cryptoPrice.fetchCryptoPrices(for: tx.coin.chain.name.lowercased(), for: "usd")
                await uxto.fetchUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
                await eth.getEthInfo(for: tx.fromAddress)
                await web3Service.fetchData(tx.fromAddress)
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
