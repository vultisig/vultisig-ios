//
//  LimitOrderCancelPreparer.swift
//  VultisigApp
//
//  Everything a cancel needs resolved between the tap on "Cancel Order" and the
//  Verify screen — the inbound vault, the dust, the fee, the balance verdict —
//  plus the unsigned transaction Verify is handed.
//
//  There is no confirmation screen in between. A cancel is deep-linked from the
//  order's detail sheet with its assets, amounts and memo already fixed, so it
//  has no editable field and nothing left to decide; the codebase already has
//  that shape in the Solana unstake/withdraw rows, which build their transaction
//  and push straight to Verify. What the removed screen SAID rides along on
//  `LimitOrderCancelRequest.disclosures` and renders on Verify, above the
//  signing button.
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-order-cancel-preparer")

enum LimitOrderCancelPreparationError: LocalizedError, Equatable {
    /// The inbound vault or the dust floor could not be resolved, so there is no
    /// safe cancel to build. Carries the message to show the user.
    case unresolved(String)

    var errorDescription: String? {
        switch self {
        case let .unresolved(message):
            return message
        }
    }
}

@MainActor
struct LimitOrderCancelPreparer {
    private let verifyLogic = SendCryptoVerifyLogic()

    /// Resolve, price and build the cancel transaction, ready to hand to Verify.
    ///
    /// Throws only when there is nothing safe to sign. A vault that cannot afford
    /// the cancel is NOT an error: it still produces a transaction, carrying the
    /// objection in its disclosures so Verify can show it and refuse to sign —
    /// the same information the removed confirmation screen put beside its
    /// disabled Continue button.
    func prepare(
        coin: Coin,
        vault: Vault,
        request: LimitOrderCancelRequest
    ) async throws -> SendTransaction {
        let isThorchainSourced = limitOrderCancelIsThorchainSourced(sourceChainRawValue: request.sourceChainRawValue)
        let destination = isThorchainSourced ? nil : try await resolveDestination(for: coin)

        // Priced ONCE, and the same figures decide both the affordability verdict
        // and the fee rows on Verify.
        //
        // ⚠️ They used to be computed twice and only one of them kept. The L1
        // branch priced a throwaway copy to validate the balance against, then
        // built the real transaction and stamped only `gas` on it — but
        // `SendCryptoLogic.gasInReadable` reads `fee` on EVM/UTXO/Cardano, and
        // `CryptoAmountFormatter.feesInReadable` reads it everywhere. So Verify
        // showed `0 ETH / $0.00` for a cancel that cost ~0.00016 ETH, on the one
        // screen where the user agrees to pay it.
        let priced: PricedCancel
        if let destination {
            priced = try await priceL1Cancel(coin: coin, vault: vault, request: request, destination: destination)
        } else {
            priced = thorchainCancelPricing(for: coin)
        }

        let builder = CancelLimitOrderTransactionBuilder(
            coin: coin,
            request: request.with(disclosures: priced.disclosures),
            l1Destination: destination
        )
        return builder
            .buildSendTransaction(vault: vault)
            .copy(gas: priced.gas, fee: priced.fee)
    }

    /// A cancel's cost and what has to be said about it, resolved together.
    private struct PricedCancel {
        let disclosures: LimitOrderCancelDisclosures
        /// Per-unit gas. What THORChain's own fee row reads.
        let gas: BigInt
        /// TOTAL fee. What EVM, UTXO and Cardano fee rows read, and what every
        /// fiat fee string reads on every chain.
        let fee: BigInt
    }

    /// The inbound vault address and the dust an L1 cancel must attach.
    ///
    /// Neither can be cached or defaulted: the vault address rotates, and
    /// `dust_threshold` is the floor below which Bifrost ignores the transaction
    /// entirely — a cancel under it burns a fee and cancels nothing.
    private func resolveDestination(for coin: Coin) async throws -> LimitOrderCancelL1Destination {
        do {
            let inbound = try await resolveThorchainInboundVault(for: coin.chain)
            let dust = try limitOrderCancelDust(for: coin, inbound: inbound)
            let natural = coin.decimal(for: dust)
            return LimitOrderCancelL1Destination(
                inboundAddress: inbound.address,
                dust: dust,
                // Exact, not display-formatted: this string IS the transaction
                // amount. Rounding it down can drop the dust below THORChain's
                // threshold, where Bifrost ignores the transaction entirely.
                dustDecimalString: exactNaturalUnitsString(dust, decimals: coin.decimals),
                dustDisplay: AmountFormatter.formatCryptoAmount(value: natural, coin: coin.toCoinMeta())
            )
        } catch {
            logger.error("Failed to resolve L1 cancel: \(error.localizedDescription, privacy: .public)")
            throw LimitOrderCancelPreparationError.unresolved(
                (error as? LocalizedError)?.errorDescription
                    ?? "limitSwap.cancel.error.dustUnavailable".localized
            )
        }
    }

    /// Price the real transaction and run the SAME balance validation the send
    /// flow uses, rather than a local `balance > dust` approximation. The dust is
    /// not the whole cost — the chain fee rides on top — and the function-call
    /// verify screen performs no up-front balance check of its own.
    private func priceL1Cancel(
        coin: Coin,
        vault: Vault,
        request: LimitOrderCancelRequest,
        destination: LimitOrderCancelL1Destination
    ) async throws -> PricedCancel {
        let provisional = CancelLimitOrderTransactionBuilder(
            coin: coin,
            request: request,
            l1Destination: destination
        ).buildSendTransaction(vault: vault)
        do {
            let feeResult = try await verifyLogic.calculateFee(tx: provisional)
            let priced = provisional.copy(gas: feeResult.gas, fee: feeResult.fee)
            let validation = verifyLogic.validateBalanceWithFee(tx: priced)
            return PricedCancel(
                disclosures: LimitOrderCancelDisclosures(
                    donatedAmount: destination.dustDisplay,
                    balanceObjection: validation.isValid ? nil : validation.errorMessage?.localized,
                    canAffordCancel: validation.isValid
                ),
                gas: feeResult.gas,
                fee: feeResult.fee
            )
        } catch {
            // Without a priced fee there is no honest balance verdict, and
            // guessing one would either block a cancel the user can afford or
            // wave through one they cannot.
            logger.error("Failed to price the L1 cancel: \(error.localizedDescription, privacy: .public)")
            throw LimitOrderCancelPreparationError.unresolved(
                "limitSwap.cancel.error.dustUnavailable".localized
            )
        }
    }

    /// The THORChain route's cost, which needs no network at all.
    ///
    /// ⚠️ **Taken from the signing constant, not from a fee fetch.**
    /// `thorchain.swift` stamps `THORChainConstants.depositGasBaseUnits` onto
    /// every `MsgDeposit` regardless of what was fetched, so the fetched figure
    /// is the second number, not this one — and a fetch that FAILS leaves zero
    /// behind, which is how Verify came to present the cancel as free. This is
    /// also the figure `limitOrderCancelThorchainDisclosures` prices
    /// affordability from, so the fee row and the "can you pay for this?"
    /// verdict cannot disagree.
    private func thorchainCancelPricing(for coin: Coin) -> PricedCancel {
        let deposit = BigInt(THORChainConstants.depositGasBaseUnits)
        return PricedCancel(
            disclosures: limitOrderCancelThorchainDisclosures(for: coin),
            gas: deposit,
            // A THORChain deposit's whole cost IS its gas — there is no separate
            // total — and the fiat fee string reads this on every chain.
            fee: deposit
        )
    }

}

/// Whether an order funded on `sourceChainRawValue` cancels via the native
/// `MsgDeposit` route rather than an L1 dust send.
///
/// All three THORChain variants count — mainnet, Chainnet and Stagenet all sign
/// a cancel the same way. Matching mainnet alone routed a Stagenet/Chainnet-funded
/// order into `resolveDestination(for:)`, which resolves an L1 inbound vault for
/// a chain that isn't one and throws `sourceChainNotRoutable` — cancel blocked
/// outright for those orders.
func limitOrderCancelIsThorchainSourced(sourceChainRawValue: String) -> Bool {
    switch Chain(rawValue: sourceChainRawValue) {
    case .thorChain, .thorChainChainnet, .thorChainStagenet:
        return true
    default:
        return false
    }
}

/// Disclosures for the THORChain route: nothing is donated, and the deposit gas
/// is the entire cost — the cancel attaches no coins at all.
///
/// Free and pure so the affordability boundary is asserted directly, without the
/// network the L1 route needs.
func limitOrderCancelThorchainDisclosures(for coin: Coin) -> LimitOrderCancelDisclosures {
    LimitOrderCancelDisclosures(
        donatedAmount: nil,
        balanceObjection: nil,
        canAffordCancel: coin.balanceDecimal >= limitOrderCancelThorchainFee(decimals: coin.decimals)
    )
}

/// The deposit gas a THORChain cancel is signed with, in human units.
///
/// Read from the shared constant so this pre-flight and the fee the signer
/// actually stamps cannot disagree — `thorchain.swift` hardcodes the same value
/// at signing regardless of what was fetched.
func limitOrderCancelThorchainFee(decimals: Int) -> Decimal {
    Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), decimals)
}

/// The verdict of the pre-sign re-check.
enum LimitOrderCancelRecheck: Equatable {
    /// Re-checked against the stored order, and it can still be cancelled.
    case stillEligible
    /// Re-checked, and the order changed under the user — it filled, expired, or
    /// already has a cancel against it.
    case orderChanged
    /// Storage was read and holds no such order, so there was nothing to
    /// re-check. Signing is permitted — a device that does not own the row has
    /// only the original eligibility decision to go on, and blocking it would
    /// make the cancel unreachable there forever — but this is deliberately NOT
    /// `.stillEligible`: nothing was verified, and the enum should not claim it
    /// was.
    case noLocalOrder
    /// The re-check could not be performed at all, because storage could not be
    /// read. NOT a verdict about the order.
    case unverifiable
}

/// Re-check an order against storage RIGHT BEFORE its cancel is signed.
///
/// The request was snapshotted before navigation and Verify can sit open
/// indefinitely. In that window the order can fill, expire, or have a cancel
/// recorded against it — none of which the snapshot knows. Signing a cancel for
/// an order that already closed spends a fee (and on L1 donates dust) for a memo
/// that can no longer match anything.
///
/// The MEMO is deliberately not rebuilt: it was fixed at snapshot time so the
/// eligibility decision and the signed bytes cannot drift. This only asks whether
/// that decision still holds.
///
/// ⚠️ **Three-valued, because a `try?` here fails OPEN on the one guard that
/// exists to stop a stale cancel.** `LimitOrderStorageService.vault` throws when
/// there is no model context, and collapsing that into "no local order" would
/// wave the signature through on the grounds that we could not look. A vault we
/// DID read that simply holds no such order is different — that is a row this
/// device does not own, there is nothing to re-check, and the original
/// eligibility decision is the best information available.
@MainActor
func limitOrderCancelRecheck(
    _ request: LimitOrderCancelRequest,
    pubKeyECDSA: String
) -> LimitOrderCancelRecheck {
    let vault: Vault?
    do {
        vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA)
    } catch {
        logger.error("Could not re-read storage before signing a cancel: \(error.localizedDescription, privacy: .public)")
        return .unverifiable
    }
    guard let vault else { return .unverifiable }
    guard let order = vault.limitOrders.first(where: { $0.id == request.orderId }) else {
        return .noLocalOrder
    }
    return limitOrderCancelEligibility(order.details).isCancellable ? .stillEligible : .orderChanged
}
