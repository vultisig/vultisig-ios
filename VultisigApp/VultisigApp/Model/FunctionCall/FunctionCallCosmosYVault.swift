//
//  FunctionCallCosmosYVault.swift
//  VultisigApp
//
//  Refactor: supports **deposit** *and* **withdraw** (re-usable UI)
//  Updated: 30/07/25  – raw JSON msgs, direct contract (no affiliate)
//
import SwiftUI
import Foundation
import Combine

// MARK: - Constants
struct YVaultConstants {
    /// Stagenet contracts – swap to mainnet after release
    static let contracts: [String: String] = [
        "rune": "sthor1552fjtt2u6evfxwmnx0w68kh7u4fqt7e6vv0du3vj5rwggumy5jsmwzjsr", // yRUNE
        "tcy" : "sthor14t7ns0zs8tfnxe8e0zke96y54g07tlwywgpms4h3aaftvdtlparskcaflv"  // yTCY
    ]
    static let depositMsgJSON = "{ \"deposit\": {} }"
    // Slippage presets used on withdraw (1 %, 2 %, 5 %, 7.5 %)
    static let slippageOptions: [Decimal] = [0.01, 0.02, 0.05, 0.075]
}

// MARK: - Action Type
enum YVaultAction {
    case deposit
    case withdraw(slippage: Decimal) // default slippage chosen in UI
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
    @Published var action: YVaultAction // 🔸 now mutable so UI can switch
    
    // Deps
    @ObservedObject var tx: SendTransaction
    private let vault: Vault
    private let contractAddress: String
    
    private var amountMicro: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: Init
    
    init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault, action: YVaultAction) {
        self.tx = tx
        self.vault = vault
        self.action = action
        let denom = tx.coin.ticker.lowercased()
        self.contractAddress = YVaultConstants.contracts[denom] ?? ""
        self.destinationAddress = self.contractAddress
        
        balanceLabel = "Amount ( Balance: \(tx.coin.balanceDecimal.formatForDisplay()) \(tx.coin.ticker.uppercased()) )"
        setupValidation()
        if case .withdraw(let slip) = action { selectedSlippage = slip }
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
        dict.set("denom", tx.coin.ticker.lowercased())
        dict.set("amount", String(amountMicro))
        return dict
    }
    
    var description: String { "yVault-\(tx.coin.ticker.uppercased())-\(actionStr)" }
    private var actionStr: String { action.isDeposit ? "deposit" : "withdraw" }
    
    
    // MARK: UI
    func getView() -> AnyView {
        AnyView(FunctionCallCosmosYVaultView(viewModel: self))
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
            // 🔹 Action selector (Deposit / Withdraw)
            GenericSelectorDropDown(
                items: Binding(
                    get: { ["Deposit", "Withdraw"].map { IdentifiableString(value: $0) } },
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
                        if sel.value.lowercased() == "deposit" {
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
            
            // Amount field (always)
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { viewModel.balanceLabel },
                    set: { viewModel.balanceLabel = $0 }
                ),
                value: Binding(
                    get: { viewModel.amount },
                    set: { viewModel.amount = $0 }
                ),
                isValid: Binding(
                    get: { viewModel.amountValid },
                    set: { viewModel.amountValid = $0 }
                )
            )
            
            // Slippage selector only in withdraw mode
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
                                // update action with new slippage
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
