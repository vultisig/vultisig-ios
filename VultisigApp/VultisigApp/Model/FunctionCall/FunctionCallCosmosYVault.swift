//
//  FunctionCallCosmosYVault.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine

// MARK: - Constants
struct YVaultConstants {
    /// Mainnet contracts
    static let contracts: [String: String] = [
        "rune": "thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt", // yRUNE
        "tcy" : "thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px",  // yTCY
        
        "yrune": "thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt", // yRUNE
        "ytcy" : "thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px"  // yTCY
    ]
    static let receiptDenominations: [String: String] = [
        "rune": "x/nami-index-nav-thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt-rcpt", // yRUNE token
        "tcy": "x/nami-index-nav-thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px-rcpt",   // yTCY token
        
        "yrune": "x/nami-index-nav-thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt-rcpt", // yRUNE token
        "ytcy": "x/nami-index-nav-thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px-rcpt"   // yTCY token
    ]
    static let depositMsgJSON = "{ \"deposit\": {} }"
    // Slippage presets used on withdraw (1 %, 2 %, 5 %, 7.5 %)
    static let slippageOptions: [Decimal] = [0.01, 0.02, 0.05, 0.075]
}

// MARK: - Action Type
enum YVaultAction {
    case deposit
    case withdraw(slippage: Decimal)
}

// MARK: - View-Model
class FunctionCallCosmosYVault: ObservableObject {
    // UI-bound fields
    @Published var amount: Decimal = 0.0 { didSet { recalcMicroAmount() } }
    @Published var amountValid = false
    @Published var isTheFormValid = false
    @Published var balanceLabel = "( Balance: -- )"
    @Published var selectedSlippage: Decimal = YVaultConstants.slippageOptions.first!
    @Published var destinationAddress: String = ""
    @Published var action: YVaultAction
    
    @ObservedObject var tx: SendTransaction
    private let vault: Vault
    private let contractAddress: String
    
    private var amountMicro: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Check if deposit is allowed for this coin
    var isDepositAllowed: Bool {
        let ticker = tx.coin.ticker.lowercased()
        return ticker == "rune" || ticker == "tcy"
    }
    
    // MARK: Init
    init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault, action: YVaultAction) {
        self.tx = tx
        self.vault = vault
        let denom = tx.coin.ticker.lowercased()
        self.contractAddress = YVaultConstants.contracts[denom] ?? ""
        self.destinationAddress = self.contractAddress
        
        // If deposit is not allowed for this coin and action is deposit, default to withdraw
        if case .deposit = action, !(denom == "rune" || denom == "tcy") {
            self.action = .withdraw(slippage: YVaultConstants.slippageOptions.first!)
        } else {
            self.action = action
        }
    }
    
    func initiate() {
        balanceLabel = "Amount ( Balance: \(tx.coin.balanceDecimal.formatForDisplay()) \(tx.coin.ticker.uppercased()) )"
        setupValidation()
        if case .withdraw(let slip) = self.action { selectedSlippage = slip }
    }
    
    // MARK: Validation
    private func setupValidation() {
        $amountValid.assign(to: \Self.isTheFormValid, on: self).store(in: &cancellables)
    }
    
    // MARK: Helpers
    private func recalcMicroAmount() {
        let decimals = tx.coin.decimals
        let multiplier = pow(10.0, Double(decimals))
        let micro = (amount * Decimal(multiplier)) as NSDecimalNumber
        amountMicro = micro.uint64Value
    }
    
    private func buildExecuteMsg() -> String {
        switch action {
        case .deposit:
            return YVaultConstants.depositMsgJSON
        case .withdraw(let slippage):
            let slipStr = String(describing: slippage)
            return "{ \"withdraw\": { \"slippage\": \"\(slipStr)\" } }"
        }
    }
    
    // MARK: Dictionary for Msg builder
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", destinationAddress)
        dict.set("executeMsg", buildExecuteMsg())
        
        let denomKey = tx.coin.ticker.lowercased()
        switch action {
        case .deposit:
            dict.set("denom", denomKey)
        case .withdraw:
            let receiptDenom = YVaultConstants.receiptDenominations[denomKey] ?? ""
            dict.set("denom", receiptDenom)
        }
        
        dict.set("amount", String(amountMicro))
        return dict
    }
    
    var description: String { "yVault-\(tx.coin.ticker.uppercased())-\(actionStr)" }
    private var actionStr: String { action.isDeposit ? "deposit" : "withdraw" }
    
    // MARK: UI
    func getView() -> AnyView {
        AnyView(FunctionCallCosmosYVaultView(viewModel: self).onAppear{
            self.initiate()
        })
    }
}

// MARK: - Helpers
private extension YVaultAction {
    var isDeposit: Bool {
        if case .deposit = self { return true } else { return false }
    }
}

// MARK: - View
struct FunctionCallCosmosYVaultView: View {
    @ObservedObject var viewModel: FunctionCallCosmosYVault
    
    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: Binding(
                    get: {
                        var options = ["Withdraw"]
                        if viewModel.isDepositAllowed {
                            options.insert("Deposit", at: 0)
                        }
                        return options.map { IdentifiableString(value: $0) }
                    },
                    set: { _ in }
                ),
                selected: Binding(
                    get: {
                        switch viewModel.action {
                        case .deposit:   return IdentifiableString(value: "Deposit")
                        case .withdraw:  return IdentifiableString(value: "Withdraw")
                        }
                    },
                    set: { sel in
                        if sel.value.lowercased() == "deposit" && viewModel.isDepositAllowed {
                            viewModel.action = .deposit
                        } else {
                            viewModel.action = .withdraw(slippage: viewModel.selectedSlippage)
                        }
                    }
                ),
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { _ in }
            )
            .padding(.bottom, 8)
            
            StyledFloatingPointField(
                label: "Amount",
                placeholder: viewModel.balanceLabel,
                value: $viewModel.amount,
                isValid: $viewModel.amountValid
            )
            
            if case .withdraw = viewModel.action {
                GenericSelectorDropDown(
                    items: Binding(
                        get: { YVaultConstants.slippageOptions.map { IdentifiableString(value: "\($0 * 100)%") } },
                        set: { _ in }
                    ),
                    selected: Binding(
                        get: { IdentifiableString(value: "\(viewModel.selectedSlippage * 100)%") },
                        set: { sel in
                            if let val = Decimal(string: sel.value.replacingOccurrences(of: "%", with: "")) {
                                viewModel.selectedSlippage = val / 100
                                viewModel.action = .withdraw(slippage: viewModel.selectedSlippage)
                            }
                        }
                    ),
                    mandatoryMessage: "*",
                    descriptionProvider: { $0.value },
                    onSelect: { _ in }
                )
            }
        }
    }
}
