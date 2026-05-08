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
//  SwapFlowSignals).
//

import BigInt
import Foundation

struct SwapTransaction: Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: Decimal
    let quote: SwapQuote
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
            feeCoin: .example
        )
    }()
}
#endif

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
            feeCoin: feeCoin
        )
    }

    /// Bridge to the value-type `SwapDraft` so existing `SwapCryptoLogic.foo(draft:)`
    /// helpers can be reused from Verify/Done. `fromCoins` is populated with just
    /// `[fromCoin, feeCoin]` — enough for the helpers that rely on it.
    var asDraft: SwapDraft {
        SwapDraft(
            fromAmount: fromAmount.description,
            thorchainFee: thorchainFee,
            gas: gas,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps,
            quote: quote,
            isFastVault: isFastVault,
            fastVaultPassword: .empty,
            pendingRetryReason: nil,
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromCoins: fromCoin == feeCoin ? [fromCoin] : [fromCoin, feeCoin],
            toCoins: [toCoin]
        )
    }
}
