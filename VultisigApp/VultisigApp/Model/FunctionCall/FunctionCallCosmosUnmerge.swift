//
//  FunctionCallCosmosUnmerge.swift
//  VultisigApp
//
//  Created on 2025/01/03.
//

import SwiftUI
import Foundation
import Combine

/**
 * THORCHAIN - FUNCTION: "EXECUTE CONTRACT - UNMERGE"
 * 
 * UI Elements:
 * • Dropdown: Select token to unmerge
 * • Amount Field: Enter amount of shares to withdraw (displayed as RUJI amount)
 * • Display: Current balance info
 * 
 * Action:
 * → Call the RUJI Merge smart contract to withdraw the specified amount
 */

class FunctionCallCosmosUnmerge: ObservableObject {
    @Published var rujiAmount: Decimal = 0.0  // This is what user enters
    @Published var sharesAmount: String = "0" // This is calculated from rujiAmount
    @Published var destinationAddress: String = ""
    @Published var fnCall: String = ""
    
    @Published var amountValid: Bool = false
    @Published var fnCallValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    @Published var tokens: [IdentifiableString] = []
    @Published var tokenValid: Bool = false
    @Published var selectedToken: IdentifiableString = .init(value: "The Unmerge")
    
    @Published var balanceLabel: String = "Amount"
    @Published var currentRujiBalance: Decimal = 0
    @Published var currentShares: String = "0"
    @Published var sharePrice: Decimal = 0
    @Published var isLoading: Bool = false
    
    @ObservedObject var tx: SendTransaction
    
    private var vault: Vault
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        
        setupValidation()
        
        // Find available merge tokens that have balances
        let availableTokens = tokensToMerge.filter { tokenInfo in
            vault.coins.contains { coin in
                coin.chain == .thorChain &&
                !coin.isNativeToken &&
                coin.ticker.lowercased() == tokenInfo.denom.lowercased().replacingOccurrences(of: "thor.", with: "")
            }
        }
        
        for token in availableTokens {
            tokens.append(.init(value: token.denom.uppercased()))
        }
        
        // Pre-select if we're already on a merged token
        if !tx.coin.isNativeToken,
           let match = tokensToMerge.first(where: {
               $0.denom.lowercased() == "thor.\(tx.coin.ticker.lowercased())"
           }) {
            selectedToken = .init(value: match.denom.uppercased())
            tokenValid = true
            destinationAddress = match.wasmContractAddress
            Task {
                await fetchMergedBalance()
            }
        } else if !tokens.isEmpty {
            // If no pre-selection, select the first available token
            selectedToken = tokens[0]
            tokenValid = true
            destinationAddress = tokensToMerge.first {
                $0.denom.lowercased() == selectedToken.value.lowercased()
            }?.wasmContractAddress ?? ""
            Task {
                await fetchMergedBalance()
            }
        }
    }
    
    @MainActor
    func fetchMergedBalance() async {
        isLoading = true
        objectWillChange.send() // Force UI update
        defer { 
            isLoading = false
            objectWillChange.send() // Force UI update
        }
        
        do {
            let thorAddress = vault.coins.first(where: { $0.chain == .thorChain })?.address ?? ""
            
            guard !thorAddress.isEmpty else {
                print("ERROR: No THORChain address found in vault")
                balanceLabel = "No THORChain address found"
                currentRujiBalance = 0
                currentShares = "0"
                sharePrice = 0
                objectWillChange.send()
                return
            }
            
            let (ruji, shares, price) = try await ThorchainService.shared.fetchRujiBalance(
                thorAddr: thorAddress,
                tokenSymbol: selectedToken.value
            )
            
            currentRujiBalance = ruji
            currentShares = shares
            sharePrice = price
            
            // Auto-fill the amount field with RUJI balance in decimal format
            let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
            rujiAmount = currentRujiBalance / divisor.decimalValue
            
            updateBalanceLabel()
            calculateSharesFromRuji() // Calculate shares for the auto-filled RUJI amount
            objectWillChange.send() // Force UI update after setting values
        } catch {
            print("Error fetching merged balance: \(error)")
            balanceLabel = "Error loading balance"
            currentRujiBalance = 0
            currentShares = "0"
            sharePrice = 0
            rujiAmount = 0
            sharesAmount = "0"
            objectWillChange.send() // Force UI update on error
        }
    }
    
    @MainActor
    private func updateBalanceLabel() {
        let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
        let rujiBalance = currentRujiBalance / divisor.decimalValue
        balanceLabel = "Amount ( Balance: \(rujiBalance.formatDecimalToLocale()) RUJI )"
        objectWillChange.send() // Force UI update
    }
    
    private func calculateSharesFromRuji() {
        guard rujiAmount > 0, sharePrice > 0 else {
            sharesAmount = "0"
            return
        }
        
        let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
        let rujiAmountInSmallestUnit = rujiAmount * divisor.decimalValue
        let sharesDecimal = rujiAmountInSmallestUnit / sharePrice
        sharesAmount = String(format: "%.0f", NSDecimalNumber(decimal: sharesDecimal).doubleValue)
    }
    
    private func setupValidation() {
        // Validate amount based on rujiAmount changes
        $rujiAmount
            .sink { [weak self] value in
                guard let self = self else { return }
                self.calculateSharesFromRuji()
                
                let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
                let maxRuji = self.currentRujiBalance / divisor.decimalValue
                self.amountValid = value > 0 && value <= maxRuji
            }
            .store(in: &cancellables)
        
        // Validate selected token
        $selectedToken
            .sink { [weak self] token in
                self?.tokenValid = token.value.lowercased() != "the unmerge"
            }
            .store(in: &cancellables)
        
        // Overall form validation
        Publishers.CombineLatest3($amountValid, $tokenValid, $fnCallValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var view: AnyView {
        return AnyView(UnmergeView(viewModel: self))
    }
    
    func getView() -> AnyView {
        return AnyView(UnmergeView(viewModel: self))
    }
    
    var formattedBalanceText: String {
        let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
        let rujiBalance = (currentRujiBalance / divisor.decimalValue).formatDecimalToLocale()
        return "\(rujiBalance) RUJI (\(currentShares) shares)"
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        let memo = "unmerge:\(selectedToken.value):\(sharesAmount)"
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", self.destinationAddress)
        dict.set("selectedToken", self.selectedToken.value)
        dict.set("sharesAmount", self.sharesAmount)
        dict.set("rujiAmount", self.rujiAmount.description)
        dict.set("memo", self.toString())
        return dict
    }
    
    struct TokenMergeInfo: Codable {
        let denom: String
        let wasmContractAddress: String
    }
    
    let tokensToMerge: [TokenMergeInfo] = [
        TokenMergeInfo(denom: "thor.kuji", wasmContractAddress: "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"),
        TokenMergeInfo(denom: "thor.rkuji", wasmContractAddress: "thor1yyca08xqdgvjz0psg56z67ejh9xms6l436u8y58m82npdqqhmmtqrsjrgh"),
        TokenMergeInfo(denom: "thor.fuzn", wasmContractAddress: "thor1suhgf5svhu4usrurvxzlgn54ksxmn8gljarjtxqnapv8kjnp4nrsw5xx2d"),
        TokenMergeInfo(denom: "thor.nstk", wasmContractAddress: "thor1cnuw3f076wgdyahssdkd0g3nr96ckq8cwa2mh029fn5mgf2fmcmsmam5ck"),
        TokenMergeInfo(denom: "thor.wink", wasmContractAddress: "thor1yw4xvtc43me9scqfr2jr2gzvcxd3a9y4eq7gaukreugw2yd2f8tsz3392y"),
        TokenMergeInfo(denom: "thor.lvn", wasmContractAddress: "thor1ltd0maxmte3xf4zshta9j5djrq9cl692ctsp9u5q0p9wss0f5lms7us4yf")
    ]
}

struct UnmergeView: View {
    @ObservedObject var viewModel: FunctionCallCosmosUnmerge
    
    var body: some View {
        VStack(spacing: 16) {
            GenericSelectorDropDown(
                items: Binding(
                    get: { viewModel.tokens },
                    set: { viewModel.tokens = $0 }
                ),
                selected: Binding(
                    get: { viewModel.selectedToken },
                    set: { viewModel.selectedToken = $0 }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    viewModel.selectedToken = asset
                    viewModel.tokenValid = asset.value.lowercased() != "the unmerge"
                    viewModel.destinationAddress = viewModel.tokensToMerge.first {
                        $0.denom.lowercased() == asset.value.lowercased()
                    }?.wasmContractAddress ?? ""
                    
                    // Reset balance before fetching new one
                    viewModel.currentRujiBalance = 0
                    viewModel.currentShares = "0" 
                    viewModel.sharePrice = 0
                    viewModel.rujiAmount = 0
                    viewModel.sharesAmount = "0"
                    viewModel.balanceLabel = "Loading..."
                    
                    Task {
                        // Add a small delay to ensure UI updates
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        await viewModel.fetchMergedBalance()
                    }
                }
            )
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                StyledFloatingPointField(
                    placeholder: Binding(
                        get: { viewModel.balanceLabel },
                        set: { viewModel.balanceLabel = $0 }
                    ),
                    value: Binding(
                        get: { viewModel.rujiAmount },
                        set: { 
                            viewModel.rujiAmount = $0
                            viewModel.objectWillChange.send()
                        }
                    ),
                    isValid: Binding(
                        get: { viewModel.amountValid },
                        set: { viewModel.amountValid = $0 }
                    )
                )
            }
        }
    }
} 