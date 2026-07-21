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
        let isThorchainSourced = Chain(rawValue: request.sourceChainRawValue) == .thorChain
        let destination = isThorchainSourced ? nil : try await resolveDestination(for: coin)

        let disclosures: LimitOrderCancelDisclosures
        if let destination {
            disclosures = try await l1Disclosures(coin: coin, vault: vault, request: request, destination: destination)
        } else {
            disclosures = thorchainDisclosures(coin: coin)
        }

        let builder = CancelLimitOrderTransactionBuilder(
            coin: coin,
            request: request.with(disclosures: disclosures),
            l1Destination: destination
        )
        var sendTx = builder.buildSendTransaction(vault: vault)
        do {
            // Pre-fetch the chain-specific gas so Verify shows a fee immediately.
            // Mirrors the Solana straight-to-Verify path: it is re-fetched there
            // anyway, so a failure here is non-fatal.
            let chainSpecific = try await BlockChainService.shared.fetchSpecific(tx: sendTx)
            sendTx = sendTx.copy(gas: chainSpecific.gas)
        } catch {
            logger.debug("Cancel gas prefetch failed: \(error.localizedDescription, privacy: .public)")
        }
        return sendTx
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
    private func l1Disclosures(
        coin: Coin,
        vault: Vault,
        request: LimitOrderCancelRequest,
        destination: LimitOrderCancelL1Destination
    ) async throws -> LimitOrderCancelDisclosures {
        let provisional = CancelLimitOrderTransactionBuilder(
            coin: coin,
            request: request,
            l1Destination: destination
        ).buildSendTransaction(vault: vault)
        do {
            let feeResult = try await verifyLogic.calculateFee(tx: provisional)
            let priced = provisional.copy(gas: feeResult.gas, fee: feeResult.fee)
            let validation = verifyLogic.validateBalanceWithFee(tx: priced)
            return LimitOrderCancelDisclosures(
                donatedAmount: destination.dustDisplay,
                balanceObjection: validation.isValid ? nil : validation.errorMessage?.localized,
                canAffordCancel: validation.isValid
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

    /// A THORChain cancel attaches nothing, so its deposit gas is the whole cost.
    private func thorchainDisclosures(coin: Coin) -> LimitOrderCancelDisclosures {
        LimitOrderCancelDisclosures(
            donatedAmount: nil,
            balanceObjection: nil,
            canAffordCancel: coin.balanceDecimal >= limitOrderCancelThorchainFee(decimals: coin.decimals)
        )
    }
}

/// The deposit gas a THORChain cancel is signed with, in human units.
///
/// Read from the shared constant so this pre-flight and the fee the signer
/// actually stamps cannot disagree — `thorchain.swift` hardcodes the same value
/// at signing regardless of what was fetched.
func limitOrderCancelThorchainFee(decimals: Int) -> Decimal {
    Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), decimals)
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
@MainActor
func limitOrderCancelIsStillEligible(_ request: LimitOrderCancelRequest, pubKeyECDSA: String) -> Bool {
    guard let vault = try? LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA),
          let order = vault.limitOrders.first(where: { $0.id == request.orderId }) else {
        // No local order — a co-signer, or a row this device does not own. The
        // original eligibility check is the best information available.
        return true
    }
    return limitOrderCancelEligibility(order.details).isCancellable
}
