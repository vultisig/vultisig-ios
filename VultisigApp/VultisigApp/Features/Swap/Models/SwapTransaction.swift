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
    let quote: SwapQuote
    /// Settlement mode. Defaults to `.standard` (so the memberwise initializer
    /// keeps it optional and existing call sites are unchanged); only the
    /// same-underlying secured path sets `.securedMint`. `var` purely so the
    /// synthesized memberwise init carries the default — the struct is still used
    /// immutably (`let`-bound everywhere, rebuilt via `with`).
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

    /// Native coin that pays for gas — `fromCoin` for native sources, the EVM-native
    /// sibling (e.g. ETH for an USDC source) otherwise. Precomputed at construction
    /// because the sibling-lookup needs access to the full source-chain coin list,
    /// which Verify/Done don't otherwise carry.
    let feeCoin: Coin

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
    var providerDisplayName: String? {
        switch mode {
        case .securedMint:
            return "Mint (SECURE+)"
        case .standard:
            return quote.displayName
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
        referralDiscountBps: Int? = nil
    ) -> SwapTransaction {
        SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            quote: quote ?? self.quote,
            mode: mode,
            gas: gas ?? self.gas,
            gasLimit: gasLimit ?? self.gasLimit,
            thorchainFee: thorchainFee ?? self.thorchainFee,
            vultDiscountBps: vultDiscountBps ?? self.vultDiscountBps,
            referralDiscountBps: referralDiscountBps ?? self.referralDiscountBps,
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
        SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
    }

    var router: String? {
        SwapCryptoLogic.router(quote: quote)
    }

    var inboundFeeDecimal: Decimal? {
        SwapCryptoLogic.inboundFeeDecimal(quote: quote, toCoin: toCoin)
    }

    var isApproveRequired: Bool {
        // A secured mint bundles an ERC20 router approval (built by the deposit
        // builder for approve-required source tokens), but its synthetic quote
        // carries no router — so gate on the source coin directly. Keying off the
        // quote router here would skip the approval-consent checkbox on Verify for
        // e.g. USDC → secured USDC even though an allowance is being signed.
        if mode == .securedMint {
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
            quote: .thorchain(ThorchainSwapQuote(
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
            )),
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
