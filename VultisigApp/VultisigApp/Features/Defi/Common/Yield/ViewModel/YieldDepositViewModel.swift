//
//  YieldDepositViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

/// Deposit form for a yield vault. Builds the deposit (and, when allowance is
/// short, a prior USDC approve) as prebuilt EVM payloads routed through the
/// shared verify pipeline.
@MainActor
final class YieldDepositViewModel: ObservableObject, Form {
    let vault: Vault
    let provider: DefiYieldProvider

    @Published var validForm: Bool = false
    @Published var isLoading = false
    @Published var needsApproval = false
    @Published var error: Error?
    @Published private(set) var usdcCoin: Coin?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?

    init(vault: Vault, providerID: DefiYieldProviderID) {
        self.vault = vault
        self.provider = DefiYieldProviderFactory.make(providerID)
        fetchUsdcCoin()
    }

    var availableAmount: Decimal {
        usdcCoin?.balanceDecimal ?? 0
    }

    var coinMeta: CoinMeta? {
        usdcCoin?.toCoinMeta()
    }

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        guard let usdcCoin else { return }
        await BalanceService.shared.updateBalance(for: usdcCoin)

        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: usdcCoin.balanceDecimal))
    }

    private func fetchUsdcCoin() {
        usdcCoin = vault.coins.first { $0.chain == provider.chain && $0.ticker == "USDC" }
    }

    private var amountBaseUnits: BigInt {
        guard let amount = Decimal(string: amountField.value) else { return .zero }
        return NoonYieldProvider.baseUnits(amount, decimals: NoonConstants.assetDecimals)
    }

    /// Builds the next payload to sign: an `approve` when allowance is short,
    /// otherwise the `deposit`. The caller routes to verify and re-enters for the
    /// deposit once the approve confirms.
    func makeNextPayload() async -> (payload: KeysignPayload, isApprove: Bool)? {
        let amount = amountBaseUnits
        guard amount > 0 else { return nil }

        isLoading = true
        defer { isLoading = false }

        do {
            if let approve = try await provider.buildApprovePayload(vault: vault, amount: amount) {
                needsApproval = true
                return (approve, true)
            }
            let deposit = try await provider.buildDepositPayload(vault: vault, amount: amount)
            needsApproval = false
            return (deposit, false)
        } catch {
            self.error = error
            return nil
        }
    }

    func displayTransaction() -> SendTransaction? {
        guard let usdcCoin else { return nil }
        return SendTransaction.empty(coin: usdcCoin, vault: vault).with(
            toAddress: NoonConstants.vaultAddress,
            amount: amountField.value
        )
    }
}
