//
//  YieldWithdrawViewModel.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Withdraw form for a yield vault. Picks the path by liquidity: an instant
/// `withdraw` when `maxWithdraw >= amount`, otherwise a queued `requestRedeem`.
/// Both build a prebuilt native-coin payload routed through the shared verify
/// pipeline with a display-only USDC transaction.
@MainActor
final class YieldWithdrawViewModel: ObservableObject {
    let vault: Vault
    let provider: DefiYieldProvider
    let availableBalance: Decimal

    @Published var amount: String = ""
    @Published var percentage: Double = 0
    @Published var isLoading = false
    @Published var error: Error?

    init(vault: Vault, providerID: DefiYieldProviderID, availableBalance: Decimal) {
        self.vault = vault
        self.provider = DefiYieldProviderFactory.make(providerID)
        self.availableBalance = availableBalance
    }

    var nativeGasBalance: Decimal {
        vault.nativeCoin(for: provider.chain)?.balanceDecimal ?? 0
    }

    var amountDecimal: Decimal {
        Decimal(string: amount) ?? 0
    }

    var isButtonDisabled: Bool {
        amount.isEmpty || amountDecimal <= 0 || amountDecimal > availableBalance || nativeGasBalance <= 0 || isLoading
    }

    func updatePercentage(from amountStr: String) {
        guard let amountDec = Decimal(string: amountStr), availableBalance > 0 else { return }
        let percent = min(Double(truncating: ((amountDec / availableBalance) * 100) as NSNumber), 100)
        if abs(percentage - percent) > 0.1 {
            percentage = percent
        }
    }

    func updateAmount(from percent: Double) {
        guard availableBalance > 0 else { return }
        let amountDec = availableBalance * Decimal(percent) / 100
        amount = amountDec.truncated(toPlaces: provider.assetDecimals).description
    }

    /// Builds the withdraw payload, picking instant vs queued by liquidity.
    /// Returns the payload and whether it is an instant withdraw (false ⇒
    /// queued `requestRedeem`).
    func buildPayload() async -> (payload: KeysignPayload, recipient: String, isInstant: Bool)? {
        guard let recipient = vault.nativeCoin(for: provider.chain)?.address else { return nil }
        guard let amountUnits = YieldAmount.baseUnits(amountDecimal, decimals: provider.assetDecimals) else {
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
        guard let usdcCoin = vault.coins.first(where: { $0.chain == provider.chain && $0.ticker == "USDC" }) else {
            return nil
        }
        return SendTransaction.empty(coin: usdcCoin, vault: vault).with(toAddress: recipient, amount: amount)
    }
}
