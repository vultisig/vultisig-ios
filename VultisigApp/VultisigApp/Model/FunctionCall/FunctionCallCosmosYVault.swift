//
//  FunctionCallCosmosYVault.swift
//  VultisigApp
//
//  Refactor: supports **deposit** *and* **withdraw** (re‑usable UI)
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

// MARK: - View‑Model
class FunctionCallCosmosYVault: ObservableObject {
    // UI‑bound fields
    @Published var amount: Decimal = 0.0 { didSet { recalcMicroAmount() } }
    @Published var amountValid = false
    @Published var isTheFormValid = false
    @Published var balanceLabel = "( Balance: -- )"
    @Published var selectedSlippage: Decimal = YVaultConstants.slippageOptions.first! // only matters for withdraw
    @Published var destinationAddress: String = ""
    
    // Deps
    @ObservedObject var tx: SendTransaction
    private let vault: Vault
    private let action: YVaultAction
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
    
    var description: String { "yVault‑\(tx.coin.ticker.uppercased())‑\(actionStr)" }
    private var actionStr: String { action.isDeposit ? "deposit" : "withdraw" }
    
    
    // MARK: Wasm Payload Helper
    /**
     Build a `WasmExecuteContractPayload` ready to be passed to `createKeysignPayload()`. Returns **nil** if mandatory fields are missing.
     - parameter sender: the wallet address that signs the Tx (`tx.fromAddress`).
     */
    func buildWasmExecuteContractPayload(sender: String) -> WasmExecuteContractPayload? {
        // Ensure we have required values
        guard !sender.isEmpty,
              !destinationAddress.isEmpty,
              !buildExecuteMsg().isEmpty,
              amountMicro > 0 else { return nil }
        
        let coin = CosmosCoin(amount: String(amountMicro),
                              denom: tx.coin.ticker.lowercased())
        return WasmExecuteContractPayload(
            senderAddress: sender,
            contractAddress: destinationAddress,
            executeMsg: buildExecuteMsg(),
            coins: [coin]
        )
    }
    
    // MARK: UI
    func getView() -> AnyView {
        AnyView(VStack {
            // Amount field (always)
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { self.balanceLabel },
                    set: { self.balanceLabel = $0 }
                ),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            .id("field-\(balanceLabel)-\(amount)")
            
            // Slippage selector only in withdraw mode
            if case .withdraw = action {
                GenericSelectorDropDown(
                    items: Binding(
                        get: { YVaultConstants.slippageOptions.map { IdentifiableString(value: "\($0 * 100)%") } },
                        set: { _ in }
                    ),
                    selected: Binding(
                        get: { IdentifiableString(value: "\(self.selectedSlippage * 100)%") },
                        set: { sel in
                            if let val = Decimal(string: sel.value.replacingOccurrences(of: "%", with: "")) {
                                self.selectedSlippage = val / 100
                            }
                        }
                    ),
                    mandatoryMessage: "*",
                    descriptionProvider: { $0.value },
                    onSelect: { _ in }
                )
            }
        })
    }
}

// MARK: - Helpers
private extension YVaultAction {
    var isDeposit: Bool {
        if case .deposit = self { return true } else { return false }
    }
}
