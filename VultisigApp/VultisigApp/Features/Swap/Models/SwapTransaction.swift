//
//  SwapTransaction.swift
//  VultisigApp
//
//  Immutable hand-off from `SwapDetailsViewModel` to the rest of the swap
//  flow. Constructed only when the user taps "Continue" and validation
//  passes; consumers (Verify / Pair / Keysign / Done) read it but never
//  mutate it. Form-time mutation lives on the details VM.
//
//  `fastVaultPassword` and `pendingRetryReason` are intentionally NOT here:
//  the password is gathered on the Pair screen (route param), and the retry
//  reason is a transient flow-signal between Keysign and Verify (carried by
//  SwapRetrySignal).
//

import BigInt
import Foundation
import SwiftUI

/// Discriminates the two kinds of swap transaction so the illegal states are
/// unrepresentable: a market swap carries an optional `SwapQuote`; a placed
/// THORChain limit order carries its `LimitOrderRecord`. Previously these were
/// two independent optionals (`quote` + `limitContext`) on `SwapTransaction`,
/// which allowed contradictory combinations and let a shared screen silently
/// forget the limit case. Construction now goes through this enum; `switch` on
/// it for any behaviour that differs between market and limit.
enum SwapKind: Hashable {
    case market(SwapQuote?)
    case limit(LimitOrderRecord)
}

struct SwapTransaction: Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: Decimal
    /// Single source of truth for "market vs limit". Construction goes through
    /// it; new consumers should `switch` on `kind` rather than the derived
    /// `quote` / `limitContext` / `isLimit` accessors below.
    let kind: SwapKind

    /// Market quote — `nil` for a limit order. Derived from `kind`; kept because
    /// the many quote-driven fee/amount helpers already accept `SwapQuote?`.
    var quote: SwapQuote? {
        if case let .market(quote) = kind { return quote }
        return nil
    }
    let gas: BigInt
    /// Oracle gas limit from chainSpecific (EVM only, zero elsewhere or before
    /// the fee data loads). Carried alongside `gas` (= maxFeePerGas for EVM) so
    /// the displayed fee can run the same `EVMSwapFee` reconciliation the
    /// signer does — the stored floor can exceed the route gas on token routes.
    let gasLimit: BigInt
    let thorchainFee: BigInt
    let vultDiscountBps: Int
    let referralDiscountBps: Int

    /// Source-chain broadcast-gas ESTIMATE for a placed LIMIT order, in the fee
    /// coin's smallest units. A dedicated field — NOT the market `thorchainFee`,
    /// whose meaning is the THORChain protocol/outbound fee that feeds
    /// `SwapCryptoLogic.fee` — so the limit fee display and persisted tx-history
    /// never depend on the market fee semantics. `.zero` for market transactions.
    /// `var` only so it can carry a default in the synthesized memberwise init
    /// (a defaulted `let` is excluded from it); set once at construction, never
    /// mutated afterwards — the "immutable hand-off" contract still holds.
    var networkFeeEstimate: BigInt = .zero

    /// Native coin that pays for gas — `fromCoin` for native sources, the EVM-native
    /// sibling (e.g. ETH for an USDC source) otherwise. Precomputed at construction
    /// because the sibling-lookup needs access to the full source-chain coin list,
    /// which Verify/Done don't otherwise carry.
    let feeCoin: Coin

    /// The placed limit order's record — `nil` for a market swap. Derived from
    /// `kind`. Lets the shared Verify / Pair / Keysign / Done screens flip to
    /// limit-specific UI without forking the screen types.
    var limitContext: LimitOrderRecord? {
        if case let .limit(record) = kind { return record }
        return nil
    }

    var isLimit: Bool {
        if case .limit = kind { return true }
        return false
    }

    /// Per-swap advanced settings (slippage / gas-limit override / external
    /// recipient) captured at hand-off. The external recipient MUST be surfaced
    /// on the verify screen before signing.
    let advancedSettings: SwapAdvancedSettings

    /// Final destination for the swapped funds: the user-set external recipient
    /// when present, otherwise the user's own address on the destination chain
    /// (today's behavior). Surfaced on the verify screen.
    var recipientAddress: String {
        advancedSettings.externalRecipient ?? toCoin.address
    }

    /// Whether an external recipient (different from the user's own address) is set.
    var hasExternalRecipient: Bool {
        advancedSettings.externalRecipient != nil
    }
}

extension SwapTransaction {
    /// Builder for refresh paths in Verify — re-fetched quote/gas/fees produce a new
    /// SwapTransaction with the same identity fields (fromCoin, toCoin, amount, etc.).
    func with(
        quote: SwapQuote? = nil,
        gas: BigInt? = nil,
        gasLimit: BigInt? = nil,
        thorchainFee: BigInt? = nil,
        vultDiscountBps: Int? = nil,
        referralDiscountBps: Int? = nil
    ) -> SwapTransaction {
        SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            // `with(quote:)` is a market-refresh helper: a new quote re-quotes a
            // market swap; with no quote we preserve the existing kind (a limit
            // order never refreshes through here).
            kind: quote.map { .market($0) } ?? self.kind,
            gas: gas ?? self.gas,
            gasLimit: gasLimit ?? self.gasLimit,
            thorchainFee: thorchainFee ?? self.thorchainFee,
            vultDiscountBps: vultDiscountBps ?? self.vultDiscountBps,
            referralDiscountBps: referralDiscountBps ?? self.referralDiscountBps,
            networkFeeEstimate: networkFeeEstimate,
            feeCoin: feeCoin,
            advancedSettings: advancedSettings
        )
    }
}

// MARK: - Convenience computed helpers
//
// Sugar over the primitive-taking SwapCryptoLogic free functions so view code
// reads `transaction.swapFeeString` instead of spelling out the args.

extension SwapTransaction {
    private var fromAmountString: String { fromAmount.description }

    var fee: BigInt {
        SwapCryptoLogic.fee(quote: quote, fromCoin: fromCoin, thorchainFee: thorchainFee)
    }

    /// Network fee value shown on the verify/done screens. For EVM aggregator/
    /// SwapKit routes this is the signed bond so the initiator matches the
    /// co-signer (`JoinKeysignGasViewModel`) and the vault's signature. Also
    /// what the verify screen's sufficiency re-validation checks against,
    /// since the bond is the node's real admission requirement.
    /// See `SwapCryptoLogic.displayedSwapNetworkFeeWei`.
    var displayedNetworkFeeWei: BigInt {
        SwapCryptoLogic.displayedSwapNetworkFeeWei(quote: quote, feeCoin: feeCoin, gas: gas, gasLimit: gasLimit, fee: fee)
    }

    var amountInCoinDecimal: BigInt {
        SwapCryptoLogic.amountInCoinDecimal(fromAmount: fromAmountString, fromCoin: fromCoin)
    }

    var toAmountDecimal: Decimal {
        // Limit orders carry no market quote (`quote == nil`) — the limit-ness
        // lives in the memo. Deriving the "you receive" amount from the quote
        // would render 0 on the shared Verify / Done screens. Use the minimum
        // output implied by the limit price instead.
        if let limit = limitContext {
            return limitOrderExpectedOutput(
                sourceAmount: BigInt(limit.sourceAmount) ?? 0,
                sourceDecimals: limit.sourceDecimals,
                targetPrice: limit.targetPrice
            )
        }
        return SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
    }

    var router: String? {
        SwapCryptoLogic.router(quote: quote)
    }

    var inboundFeeDecimal: Decimal? {
        SwapCryptoLogic.inboundFeeDecimal(quote: quote, toCoin: toCoin)
    }

    var isApproveRequired: Bool {
        SwapCryptoLogic.isApproveRequired(fromCoin: fromCoin, quote: quote)
    }

    var isDeposit: Bool {
        SwapCryptoLogic.isDeposit(fromCoin: fromCoin)
    }

    // MARK: - Display

    var fromFiatAmount: String {
        SwapCryptoLogic.fromFiatAmount(fromCoin: fromCoin, fromAmount: fromAmountString)
    }

    var toFiatAmount: String {
        SwapCryptoLogic.toFiatAmount(toCoin: toCoin, quote: quote)
    }

    var showGas: Bool {
        SwapCryptoLogic.showGas(gas: gas)
    }

    var showFees: Bool {
        SwapCryptoLogic.showFees(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var showTotalFees: Bool {
        SwapCryptoLogic.showTotalFees(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: fee)
    }

    /// Whether an expandable fee breakdown has any rows to show. Mirrors the
    /// rows the swap fee surfaces emit (swap fee and/or network gas), so a
    /// "Total fee" chevron is only offered when expanding reveals something.
    /// `showTotalFees` can be true while both components are suppressed — for
    /// quote-driven EVM swaps `totalFeeString` keys off `fee` while `showGas`
    /// keys off `gas`, a distinct gas price.
    var hasFeeBreakdown: Bool {
        showFees || showGas
    }

    var swapFeeString: String {
        SwapCryptoLogic.swapFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapGasString: String {
        SwapCryptoLogic.swapGasString(quote: quote, feeCoin: feeCoin, gas: gas, fee: displayedNetworkFeeWei)
    }

    /// Fiat sub-line of the network-fee cell on the verify/done screens. Uses the
    /// displayed network fee so the crypto and fiat agree (and match the co-signer).
    var approveFeeString: String {
        SwapCryptoLogic.approveFeeString(feeCoin: feeCoin, fee: displayedNetworkFeeWei)
    }

    var isApproveFeeZero: Bool {
        SwapCryptoLogic.isApproveFeeZero(fee: fee)
    }

    var totalFeeString: String {
        SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: displayedNetworkFeeWei)
    }

    /// Network-fee crypto string for a placed LIMIT order. The limit "fee" is
    /// JUST the source-chain broadcast gas, pre-estimated into `networkFeeEstimate`
    /// (fee coin's smallest units) at place time — a resting `=<` order carries
    /// no market quote, so the quote-driven `fee` / `totalFeeString` are zero /
    /// empty for it. Empty until the estimate is available.
    var limitNetworkFeeString: String {
        SwapCryptoLogic.limitNetworkFeeString(feeCoin: feeCoin, fee: networkFeeEstimate)
    }

    /// Fiat sub-line for `limitNetworkFeeString`.
    var limitNetworkFeeFiat: String {
        SwapCryptoLogic.limitNetworkFeeFiat(feeCoin: feeCoin, fee: networkFeeEstimate)
    }

    var fromAmountDecimal: Decimal { fromAmount }

    var durationString: String {
        SwapCryptoLogic.durationString(quote: quote)
    }

    var baseAffiliateFee: String {
        SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapFeeLabel: String {
        SwapCryptoLogic.swapFeeLabel(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fromAmount: fromAmountString)
    }

    var outboundFeeString: String {
        SwapCryptoLogic.outboundFeeString(quote: quote, toCoin: toCoin)
    }

    var vultDiscountLabel: String {
        SwapCryptoLogic.vultDiscountLabel(vultDiscountBps: vultDiscountBps)
    }

    var referralDiscountLabel: String {
        SwapCryptoLogic.referralDiscountLabel(referralDiscountBps: referralDiscountBps)
    }

    var vultDiscount: String {
        SwapCryptoLogic.vultDiscount(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmountString, vultDiscountBps: vultDiscountBps
        )
    }

    var referralDiscount: String {
        SwapCryptoLogic.referralDiscount(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmountString, vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    var priceImpactString: String {
        SwapCryptoLogic.priceImpactString(quote: quote)
    }

    var priceImpactColor: Color {
        SwapCryptoLogic.priceImpactColor(quote: quote)
    }

    func progressLink(hash: String) -> String? {
        SwapCryptoLogic.progressLink(quote: quote, fromCoin: fromCoin, hash: hash)
    }
}

#if DEBUG
extension SwapTransaction {
    /// Preview-only fixture. Real swaps construct via `SwapDetailsViewModel.makeTransaction()`.
    static let example: SwapTransaction = {
        SwapTransaction(
            fromCoin: .example,
            toCoin: .example,
            fromAmount: 0,
            kind: .market(.thorchain(ThorchainSwapQuote(
                dustThreshold: nil,
                expectedAmountOut: "0",
                expiry: 0,
                fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
                inboundAddress: nil,
                inboundConfirmationBlocks: nil,
                inboundConfirmationSeconds: nil,
                memo: "",
                notes: "",
                outboundDelayBlocks: 0,
                outboundDelaySeconds: 0,
                recommendedMinAmountIn: "0",
                slippageBps: nil,
                totalSwapSeconds: nil,
                warning: "",
                router: nil,
                maxStreamingQuantity: nil
            ))),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: .example,
            advancedSettings: .default
        )
    }()
}
#endif
