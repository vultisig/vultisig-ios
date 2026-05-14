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

struct SwapTransaction: Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: Decimal
    /// `nil` when the transaction is a limit order — limit flows have no
    /// market quote. All quote-derived computed properties already accept
    /// `SwapQuote?` so the nil-safety cascades cleanly via SwapCryptoLogic.
    let quote: SwapQuote?
    let gas: BigInt
    let thorchainFee: BigInt
    let vultDiscountBps: Int
    let referralDiscountBps: Int
    let isFastVault: Bool

    /// Native coin that pays for gas — `fromCoin` for native sources, the EVM-native
    /// sibling (e.g. ETH for an USDC source) otherwise. Precomputed at construction
    /// because the sibling-lookup needs access to the full source-chain coin list,
    /// which Verify/Done don't otherwise carry.
    let feeCoin: Coin

    /// Non-nil iff this transaction represents a placed THORChain limit
    /// order. Lets the shared Verify / Pair / Keysign / Done screens flip
    /// to limit-specific UI (`isLimit`) without forking the screen types.
    let limitContext: LimitOrderRecord?

    var isLimit: Bool { limitContext != nil }
}

extension SwapTransaction {
    /// Builder for refresh paths in Verify — re-fetched quote/gas/fees produce a new
    /// SwapTransaction with the same identity fields (fromCoin, toCoin, amount, etc.).
    func with(
        quote: SwapQuote? = nil,
        gas: BigInt? = nil,
        thorchainFee: BigInt? = nil,
        vultDiscountBps: Int? = nil,
        referralDiscountBps: Int? = nil
    ) -> SwapTransaction {
        SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            quote: quote ?? self.quote,
            gas: gas ?? self.gas,
            thorchainFee: thorchainFee ?? self.thorchainFee,
            vultDiscountBps: vultDiscountBps ?? self.vultDiscountBps,
            referralDiscountBps: referralDiscountBps ?? self.referralDiscountBps,
            isFastVault: isFastVault,
            feeCoin: feeCoin,
            limitContext: limitContext
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
        SwapCryptoLogic.fee(quote: quote, thorchainFee: thorchainFee)
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

    var swapFeeString: String {
        SwapCryptoLogic.swapFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapGasString: String {
        SwapCryptoLogic.swapGasString(quote: quote, feeCoin: feeCoin, gas: gas, fee: fee)
    }

    var approveFeeString: String {
        SwapCryptoLogic.approveFeeString(feeCoin: feeCoin, fee: fee)
    }

    var isApproveFeeZero: Bool {
        SwapCryptoLogic.isApproveFeeZero(fee: fee)
    }

    var totalFeeString: String {
        SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: fee)
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
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            isFastVault: false,
            feeCoin: .example,
            limitContext: nil
        )
    }()
}
#endif
