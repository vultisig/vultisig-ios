//
//  YieldWithdrawViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

/// Withdraw form for a yield vault. Picks the path by liquidity: an instant
/// `withdraw` when `maxWithdraw >= amount`, otherwise a queued `requestRedeem`.
/// Both build a prebuilt native-coin payload routed through the shared verify
/// pipeline with a display-only USDC transaction.
@MainActor
final class YieldWithdrawViewModel: ObservableObject, Form {
    let vault: Vault
    let provider: DefiYieldProvider
    let availableBalance: Decimal

    @Published var percentageSelected: Double? = 100
    @Published var validForm: Bool = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?

    init(vault: Vault, providerID: DefiYieldProviderID, availableBalance: Decimal) {
        self.vault = vault
        self.provider = DefiYieldProviderFactory.make(providerID)
        self.availableBalance = availableBalance
    }

    var coinMeta: CoinMeta? {
        usdcCoin?.toCoinMeta()
    }

    var nativeGasBalance: Decimal {
        vault.nativeCoin(for: provider.chain)?.balanceDecimal ?? 0
    }

    /// Defaults the form to a full (100%) withdraw and installs the balance
    /// validator. The shared `AmountTextField` fills the amount from the 100%
    /// selection, so the form opens pre-filled with the whole position.
    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: availableBalance))
        percentageSelected = 100
    }

    /// Builds the withdraw payload, picking instant vs queued by liquidity.
    /// Returns the payload, recipient, and whether it is an instant withdraw
    /// (false ⇒ queued `requestRedeem`).
    func buildPayload() async -> (payload: KeysignPayload, recipient: String, isInstant: Bool)? {
        guard let recipient = vault.nativeCoin(for: provider.chain)?.address else { return nil }
        guard let amountUnits = YieldAmount.baseUnits(amountField.value.toDecimal(), decimals: provider.assetDecimals) else {
            error = DefiYieldError.invalidAmount
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let instant = await provider.canWithdrawInstantly(vault: vault, amount: amountUnits)
            let payload: KeysignPayload
            if instant {
                payload = try await provider.buildWithdrawPayload(vault: vault, recipient: recipient, amount: amountUnits)
            } else {
                payload = try await provider.buildRequestRedeemPayload(vault: vault, recipient: recipient, amount: amountUnits)
            }
            return (payload, recipient, instant)
        } catch {
            self.error = error
            return nil
        }
    }

    func displayTransaction(recipient: String) -> SendTransaction? {
        guard let usdcCoin else { return nil }
        return SendTransaction.empty(coin: usdcCoin, vault: vault).with(toAddress: recipient, amount: amountField.value)
    }

    private var usdcCoin: Coin? {
        vault.coins.first { $0.chain == provider.chain && $0.ticker == "USDC" }
    }
}
