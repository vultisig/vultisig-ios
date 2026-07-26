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
///
/// Orthogonal to `SwapMode`: `kind` is *what the user is placing* (market vs
/// resting limit order), `mode` is *how a market swap settles* (pool swap vs
/// SECURE+ mint). A limit order is always `mode == .standard`.
enum SwapKind: Hashable {
    case market(SwapQuote?)
    case limit(LimitOrderRecord)
}

/// How the swap flow settles. `.standard` is the normal pool/aggregator swap.
/// `.securedMint` is the inline same-underlying case (the user holds the L1
/// asset and picks its own secured form, e.g. BTC → secured BTC): instead of a
/// wasteful ~1:1 pool swap, the flow mints via a SECURE+ deposit. The pool-quote
/// fetch is skipped, a synthetic ~1:1 quote is displayed, and at confirm the
/// SECURE+ deposit keysign payload is built instead of a swap payload.
enum SwapMode: Hashable {
    case standard
    case securedMint
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

    /// Settlement mode. Defaults to `.standard` (so the memberwise initializer
    /// keeps it optional and existing call sites are unchanged); only the
    /// same-underlying secured path sets `.securedMint`. `var` purely so the
    /// synthesized memberwise init carries the default — the struct is still used
    /// immutably (`let`-bound everywhere, rebuilt via `with`).
    ///
    /// Only meaningful for `.market` kinds: a placed limit order settles through
    /// the THORChain limit memo, never a SECURE+ mint, so it stays `.standard`.
    var mode: SwapMode = .standard
    let gas: BigInt
    /// Oracle gas limit from chainSpecific (EVM only, zero elsewhere or before
    /// the fee data loads). Carried alongside `gas` (= maxFeePerGas for EVM) so
    /// the displayed fee can run the same `EVMSwapFee` reconciliation the
    /// signer does — the stored floor can exceed the route gas on token routes.
    let gasLimit: BigInt
    let thorchainFee: BigInt
    let vultDiscountBps: Int
    let referralDiscountBps: Int

    /// Whether a referral code was active when this quote was fetched. Used by
    /// the route-aware affiliate-percentage label to reproduce the exact
    /// `affiliate_bps` the request builder sent — a clean bit, because
    /// `referralDiscountBps` collapses to 0 in DEBUG (base rate 0) even when
    /// referred. `var` with a default so the memberwise init stays source-
    /// compatible; set once at construction, never mutated (immutable hand-off).
    var isReferred: Bool = false

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

    /// Provider label for the verify/summary screens. Secured mints aren't a
    /// third-party route, so they read "Mint (SECURE+)" rather than the synthetic
    /// quote's "THORChain". Non-localized, matching the other brand display names.
    ///
    /// `nil` for a placed limit order: it carries no market quote, so there is no
    /// provider row to show — the caller's `if let` drops the row, matching the
    /// limit flow's existing Verify layout.
    var providerDisplayName: String? {
        switch mode {
        case .securedMint:
            return "Mint (SECURE+)"
        case .standard:
            // `flatMap`, not `?.`: `quote` is optional (limit orders have none)
            // AND `displayName` is itself `String?`, so `?.` would nest to
            // `String??`.
            return quote.flatMap(\.displayName)
        }
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
        referralDiscountBps: Int? = nil,
        isReferred: Bool? = nil
    ) -> SwapTransaction {
        SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            // `with(quote:)` is a market-refresh helper: a new quote re-quotes a
            // market swap; with no quote we preserve the existing kind (a limit
            // order never refreshes through here).
            kind: quote.map { .market($0) } ?? self.kind,
            // A refresh never changes how the swap settles — a secured mint that
            // re-quotes is still a secured mint.
            mode: mode,
            gas: gas ?? self.gas,
            gasLimit: gasLimit ?? self.gasLimit,
            thorchainFee: thorchainFee ?? self.thorchainFee,
            vultDiscountBps: vultDiscountBps ?? self.vultDiscountBps,
            referralDiscountBps: referralDiscountBps ?? self.referralDiscountBps,
            isReferred: isReferred ?? self.isReferred,
            networkFeeEstimate: networkFeeEstimate,
            feeCoin: feeCoin,
            advancedSettings: advancedSettings
        )
    }
}

// MARK: - Convenience computed helpers
//
// Sugar over the primitive-taking SwapCryptoLogic free functions so view code
// reads `transaction.baseAffiliateFee` instead of spelling out the args.

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
        // output implied by the limit price instead — or the exact effective
        // minimum when the memo's LIM was rounded up to fit its byte budget, so
        // the displayed floor matches the signed order.
        if let limit = limitContext {
            if let override = limit.minOutputOverride {
                return override
            }
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
        // Two distinct paths sign an ERC20 router approval that the quote-derived
        // check below cannot see, because neither has a router-bearing market
        // quote. Both must gate on the source coin directly, or Verify silently
        // omits the approval-consent checkbox while an allowance IS being signed:
        //
        //  - Limit orders carry no market quote at all (`quote == nil`), yet an
        //    ERC20 source still deposits through the router (approve +
        //    depositWithExpiry, attached by the limit assembler).
        //  - A secured mint bundles an ERC20 router approval (built by the deposit
        //    builder for approve-required source tokens), but its synthetic quote
        //    carries no router — e.g. USDC → secured USDC.
        //
        // Both mirror the assembler/builder condition (`fromCoin.shouldApprove` =
        // EVM token source). The two are orthogonal, so this must stay an OR:
        // dropping either side reintroduces that side's missing-consent bug.
        if isLimit || mode == .securedMint {
            return fromCoin.shouldApprove
        }
        return SwapCryptoLogic.isApproveRequired(fromCoin: fromCoin, quote: quote)
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

    /// Whether the itemized "Vultisig Fee" affiliate row should render (every
    /// market swap route, even at 0%; not secured mints or limit orders).
    var showAffiliateFeeRow: Bool {
        SwapCryptoLogic.showAffiliateFeeRow(quote: quote, mode: mode)
    }

    /// Whether the "Protocol Fee" (native outbound) row should render.
    var showProtocolFeeRow: Bool {
        SwapCryptoLogic.showProtocolFeeRow(quote: quote, toCoin: toCoin, mode: mode)
    }

    /// Whether an expandable fee breakdown has any itemized rows to show, so the
    /// "Total fee" chevron is only offered when expanding reveals something.
    /// Mirrors the itemized rows the Done breakdown emits (network gas, the
    /// Vultisig affiliate row, the protocol/outbound row).
    var hasFeeBreakdown: Bool {
        showGas || showAffiliateFeeRow || showProtocolFeeRow
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
        SwapCryptoLogic.swapFeeLabel(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmountString, vultDiscountBps: vultDiscountBps, isReferred: isReferred
        )
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
