//
//  CancelLimitOrderTransactionViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "cancel-limit-order")

@MainActor
final class CancelLimitOrderTransactionViewModel: ObservableObject {
    let coin: Coin
    let vault: Vault
    let request: LimitOrderCancelRequest

    /// `nil` until resolved, and permanently `nil` for a THORChain-sourced
    /// cancel, which needs no destination and attaches nothing.
    @Published private(set) var l1Destination: LimitOrderCancelL1Destination?
    @Published private(set) var isResolving = false
    @Published private(set) var resolutionError: String?
    /// Localized key when the vault cannot cover the dust plus the real chain
    /// fee. `nil` means "no objection", which is why it is only trusted
    /// alongside a resolved destination.
    @Published private(set) var l1BalanceErrorKey: String?

    private let verifyLogic = SendCryptoVerifyLogic()

    init(coin: Coin, vault: Vault, request: LimitOrderCancelRequest) {
        self.coin = coin
        self.vault = vault
        self.request = request
    }

    /// True when the cancel is a THORChain `MsgDeposit` rather than a send from
    /// the order's own chain.
    var isThorchainSourced: Bool {
        Chain(rawValue: request.sourceChainRawValue) == .thorChain
    }

    /// Resolve the inbound vault, the dust, and whether the vault can actually
    /// pay for the transaction — all before the user can sign.
    ///
    /// The inbound vault address rotates and `dust_threshold` is the floor below
    /// which Bifrost silently ignores the transaction, so neither can be cached
    /// or defaulted.
    func onLoad() async {
        guard !isThorchainSourced, !isResolving, l1Destination == nil else { return }
        isResolving = true
        // Cleared on every attempt. `.task` can re-run, and a stale error from a
        // previous failure would otherwise keep `transactionBuilder` nil forever
        // even after a successful retry.
        resolutionError = nil
        l1BalanceErrorKey = nil
        defer { isResolving = false }
        do {
            let inbound = try await resolveThorchainInboundVault(for: coin.chain)
            let dust = try limitOrderCancelDust(for: coin, inbound: inbound)
            let natural = coin.decimal(for: dust)
            let destination = LimitOrderCancelL1Destination(
                inboundAddress: inbound.address,
                dust: dust,
                dustDecimalString: natural.formatForDisplay(maxDecimals: coin.decimals),
                dustDisplay: AmountFormatter.formatCryptoAmount(value: natural, coin: coin.toCoinMeta())
            )

            // Price the real transaction and run the SAME balance validation the
            // send flow uses, rather than a local `balance > dust` approximation.
            // The dust is not the whole cost — the chain fee rides on top — and
            // the function-call verify screen performs no up-front balance check
            // of its own: it surfaces `notEnoughBalanceError` only once payload
            // construction fails, which is an error alert where this feature's
            // standard everywhere else is a disabled button with a reason.
            let provisional = CancelLimitOrderTransactionBuilder(
                coin: coin,
                request: request,
                l1Destination: destination
            ).buildSendTransaction(vault: vault)
            let feeResult = try await verifyLogic.calculateFee(tx: provisional)
            let priced = provisional.copy(gas: feeResult.gas, fee: feeResult.fee)
            let validation = verifyLogic.validateBalanceWithFee(tx: priced)

            l1Destination = destination
            l1BalanceErrorKey = validation.isValid ? nil : validation.errorMessage
        } catch {
            // Surfaced rather than swallowed. Without a destination, a verified
            // dust floor and a priced fee there is no safe cancel to build.
            logger.error("Failed to resolve L1 cancel: \(error.localizedDescription, privacy: .public)")
            resolutionError = (error as? LocalizedError)?.errorDescription
                ?? "limitSwap.cancel.error.dustUnavailable".localized
        }
    }

    /// The deposit gas a THORChain cancel is signed with, in human units. Read
    /// from the shared constant so this pre-flight and the signed fee cannot
    /// disagree. Unused on the L1 route, which prices its fee for real above.
    var feeDecimal: Decimal {
        Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), coin.decimals)
    }

    /// What the cancel costs BEYOND the network fee: nothing on THORChain, the
    /// donated dust on L1. Shown before signing because it is unrecoverable.
    var donatedAmountDisplay: String? {
        l1Destination?.dustDisplay
    }

    /// A THORChain cancel attaches nothing, so its deposit gas is the whole
    /// cost. An L1 cancel is validated against dust + the priced chain fee in
    /// `onLoad`; this only reports that verdict, and reports `false` until it
    /// has one.
    var hasSufficientBalance: Bool {
        guard isThorchainSourced else {
            return l1Destination != nil && l1BalanceErrorKey == nil
        }
        return coin.balanceDecimal >= feeDecimal
    }

    /// The balance objection, if any, for display alongside the disabled button.
    var balanceErrorMessage: String? {
        l1BalanceErrorKey.map { $0.localized }
    }

    /// True when another resting order shares this one's THORChain bucket, so
    /// the cancel may close a different order than the one the user opened.
    var hasDuplicateWarning: Bool {
        request.duplicateRestingOrderCount > 0
    }

    /// `nil` until everything the signer needs is in hand. For L1 that includes
    /// the resolved destination — building without it would address the memo to
    /// an empty string.
    var transactionBuilder: TransactionBuilder? {
        guard resolutionError == nil, hasSufficientBalance else { return nil }
        if !isThorchainSourced, l1Destination == nil { return nil }
        return CancelLimitOrderTransactionBuilder(
            coin: coin,
            request: request,
            l1Destination: l1Destination
        )
    }
}
