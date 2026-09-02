//
//  SwapCryptoLogic.swift
//  VultisigApp
//
//  Created by Vultisig on 2025-02-03.
//
//  Pure helpers for the swap flow. Every function takes only the primitives
//  it actually reads — no shared draft/store type. Both `SwapDetailsViewModel`
//  (form state) and `SwapTransaction` (immutable hand-off) feed their own
//  fields in via convenience computed properties (defined in their own files).
//

import BigInt
import Foundation
import SwiftUI

// swiftlint:disable file_length

enum SwapCryptoLogic {
    // MARK: - Errors

    enum Errors: String, Error, LocalizedError, SwapErrorPresentable {
        case unexpectedError
        case insufficientFunds
        case insufficientGas
        case swapAmountTooSmall
        case inboundAddress
        case sameAsset

        var errorTitle: String {
            switch self {
            case .unexpectedError: return "swapErrorUnexpectedTitle".localized
            case .insufficientFunds: return "swapErrorInsufficientFundsTitle".localized
            case .insufficientGas: return "swapErrorInsufficientGasTitle".localized
            case .swapAmountTooSmall: return "swapErrorAmountTooSmallTitle".localized
            case .inboundAddress: return "swapErrorInboundAddressTitle".localized
            case .sameAsset: return "swapErrorSameAssetTitle".localized
            }
        }

        var errorDescription: String? {
            switch self {
            case .unexpectedError: return "swapErrorUnexpectedDescription".localized
            case .insufficientFunds: return "swapErrorInsufficientFundsDescription".localized
            case .insufficientGas: return "swapErrorInsufficientGasDescription".localized
            case .swapAmountTooSmall: return "swapErrorAmountTooSmallDescription".localized
            case .inboundAddress: return "swapErrorInboundAddressDescription".localized
            case .sameAsset: return "swapErrorSameAssetDescription".localized
            }
        }

        /// Every case has a localized description, so the body is that string;
        /// the coalesce only satisfies `LocalizedError`'s optional return type.
        var errorMessage: String {
            errorDescription ?? Errors.unexpectedError.errorDescription ?? ""
        }
    }

    // MARK: - Constants

    /// Affiliate is always enabled for this app's swap flow today; surfaced as a
    /// constant so the call sites read explicitly.
    static let isAffiliate = true

    // MARK: - Amount conversions

    static func fromAmountDecimal(fromAmount: String) -> Decimal {
        fromAmount.toDecimal()
    }

    static func amountInCoinDecimal(fromAmount: String, fromCoin: Coin) -> BigInt {
        let amount = fromAmount.toDecimal()
        let raw = fromCoin.raw(for: amount)

        // `raw(for:)` rounds UP, and the amount text round-trips through
        // `NumberFormatter`, which keeps only ~16 significant digits and rounds
        // half-up. A 100% preset on an 18-decimal asset therefore parses back a
        // hair ABOVE the balance and would broadcast more base units than the
        // wallet holds — a transaction the chain rejects.
        //
        // This is the broadcast amount, so the invariant is simply that it can
        // never exceed the balance. Over-spends are caught elsewhere, on a
        // separate `Decimal` path (`balanceError` compares `fromAmount` against
        // `balanceDecimal` and never calls this), so capping here hides nothing
        // from the insufficient-funds check.
        //
        // Skip the cap at zero. `Coin.init` seeds `rawBalance` to `String.zero`
        // ("0"), so a coin whose balance hasn't loaded is indistinguishable
        // from a genuinely empty wallet — there is no separate unloaded
        // sentinel to branch on. Capping on zero would therefore zero out a
        // valid amount every time the swap form renders before balances land,
        // which is the far worse failure: an empty wallet is already rejected
        // by `balanceError` on the `Decimal` path above.
        let rawBalance = fromCoin.rawBalance.toBigInt()
        guard rawBalance > 0 else { return raw }
        return min(raw, rawBalance)
    }

    /// Amount string for a "25 / 50 / 75 / 100%" preset on the swap source
    /// coin, or `nil` for a percentage the buttons don't offer.
    ///
    /// A native 100% has to leave the network fee behind; every other preset is
    /// a straight fraction of the balance. Lives here rather than in the view
    /// so the math is testable on its own.
    static func percentageAmountText(percentage: Int, fromCoin: Coin, fee: BigInt) -> String? {
        guard [25, 50, 75, 100].contains(percentage) else { return nil }

        let rawBalance = fromCoin.rawBalance.toBigInt()
        let spendable = percentage == 100 && fromCoin.isNativeToken
            ? max(rawBalance - fee, .zero)
            : rawBalance

        return PercentageAmountLogic.amountText(
            percentage: percentage,
            rawBalance: spendable,
            coinDecimals: fromCoin.decimals
        )
    }

    // MARK: - Quote-derived

    static func fee(quote: SwapQuote?, fromCoin: Coin, thorchainFee: BigInt) -> BigInt {
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return thorchainFee
        case let .oneinch(_, fee), let .kyberswap(_, fee), let .lifi(_, fee, _):
            return fee ?? 0
        case let .swapkit(_, fee, _):
            // SwapKit's wire `inbound` fee for UTXO/Cardano sources doesn't
            // reflect the realized on-chain miner fee — it renders as a
            // misleadingly small amount on the Network Fee row (e.g. a BTC swap
            // showing 0.0000008 BTC). For these chains compute the fee the same
            // way Send does: from the WalletCore transaction plan, carried in
            // `thorchainFee` (populated in `SwapDetailsViewModel.updateFees`).
            // EVM/other SwapKit sources keep the wire-reported inbound fee.
            switch fromCoin.chain.chainType {
            case .UTXO, .Cardano:
                return thorchainFee
            default:
                return fee ?? 0
            }
        case let .jupiter(_, fee, _, _):
            // Jupiter exposes no network fee at quote time; fall back to the
            // Solana-source plan fee carried in `thorchainFee`
            // (`chainSpecific.gas`), the same way Send computes it.
            return fee ?? thorchainFee
        case nil:
            return .zero
        }
    }

    // MARK: - EVM signed network fee (shared with the co-signer)

    /// Network fee value the initiator shows on the swap details/verify/done
    /// screens. For EVM aggregator/SwapKit routes it's the SIGNED bond: the
    /// shared `EVMSwapFee` reconciliation of the quote's own gas parameters
    /// (`evmQuoteGasPriceWei`, `evmRouteGas`) with the fee oracle (`gas`
    /// carries `maxFeePerGas`, `gasLimit` the oracle limit) — the same
    /// calculator the signer and the co-signer (`JoinKeysignGasViewModel`)
    /// consume, so both devices show what the vault commits to. Everything
    /// else — native-protocol swaps, routes without an EVM quote gas, or
    /// before the oracle fee has loaded (`gas == 0`) — keeps the existing
    /// quote fee. The insufficient-gas validation checks against this same
    /// value: the bond is what an EVM node requires the account to cover, so
    /// validating against the smaller quote seed lets swaps through that the
    /// node then rejects with "insufficient funds for gas".
    static func displayedSwapNetworkFeeWei(quote: SwapQuote?, feeCoin: Coin, gas: BigInt, gasLimit: BigInt, fee: BigInt) -> BigInt {
        guard feeCoin.chain.chainType == .EVM, gas > 0, let routeGas = quote?.evmRouteGas else {
            return fee
        }
        return EVMSwapFee.effective(
            quoteGasPriceWei: quote?.evmQuoteGasPriceWei ?? .zero,
            quoteGas: routeGas,
            maxFeePerGasWei: gas,
            gasLimit: gasLimit
        ).feeWei
    }

    static func toAmountDecimal(quote: SwapQuote?, toCoin: Coin) -> Decimal {
        guard let quote else { return .zero }
        switch quote {
        case let .mayachain(quote),
             let .thorchain(quote),
             let .thorchainChainnet(quote),
             let .thorchainStagenet(quote):
            let expected = quote.expectedAmountOut.toDecimal()
            return expected / toCoin.thorswapMultiplier
        case let .oneinch(quote, _), let .lifi(quote, _, _), let .kyberswap(quote, _):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        case let .jupiter(quote, _, _, _):
            // `outAmount` is already net of the affiliate fee (deducted from the
            // output and reported separately), so it's what the user receives —
            // same as LiFi above. Do NOT subtract the fee again.
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        case let .swapkit(response, _, _):
            // SwapKit returns human-units decimal strings, not raw base units.
            return Decimal(string: response.expectedBuyAmount) ?? .zero
        }
    }

    /// The minimum destination amount the transaction this swap will sign
    /// actually enforces, in `toCoin` units — or `nil` when the route enforces
    /// nothing this app can see.
    ///
    /// Only the native routes assert a floor: THORChain / MayaChain bake
    /// `LIM = expected_amount_out × (10_000 − liquidity_tolerance_bps) / 10_000`
    /// into the memo they return, and that memo is signed verbatim. So the floor
    /// is read back out of the memo — after the same `OP_RETURN` compression the
    /// payload builder applies — rather than re-derived from the tolerance we
    /// sent. The node owns the rounding and the streaming split; a client-side
    /// re-derivation would drift from it, which is the whole reason the displayed
    /// "minimum" was wrong to begin with.
    ///
    /// `nil` for every aggregator route (1inch / KyberSwap / LI.FI / Jupiter /
    /// SwapKit): they return opaque calldata or a pre-built transaction, so
    /// whatever floor their own router enforces is not exposed here. `nil` too
    /// when the memo asserts `LIM 0` — what a user-set 0% slippage produces —
    /// because that swap genuinely has no floor. Callers must render no minimum
    /// in those cases, never a stand-in.
    static func signedMinimumOutput(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin) -> Decimal? {
        guard let quote else { return nil }
        switch quote {
        case let .mayachain(quote),
             let .thorchain(quote),
             let .thorchainChainnet(quote),
             let .thorchainStagenet(quote):
            let signedMemo = ThorchainMemoLimit.signedMemo(quote.memo, sourceChain: fromCoin.chain)
            guard let limit = ThorchainMemoLimit.assertedLimit(in: signedMemo) else { return nil }
            return Decimal(limit) / toCoin.thorswapMultiplier
        case .oneinch, .kyberswap, .lifi, .jupiter, .swapkit:
            return nil
        }
    }

    /// The "min. payout: 0.00032334 ETH" line that sits under a swap's
    /// destination amount. Built here rather than at each call site so the
    /// initiator's verify screen and the co-signer's confirm screen render the
    /// identical string for the identical swap — the point of showing it at all
    /// is that both devices consent to the same number.
    static func minPayoutCaption(amount: Decimal, ticker: String) -> String {
        "\("minPayout".localized): \(amount.formatForDisplay()) \(ticker)"
    }

    static func router(quote: SwapQuote?) -> String? {
        quote?.router
    }

    /// Display-only indicative out-amount derived from the spot fiat prices the
    /// app already holds: `fromAmount × (fromPrice / toPrice)`. Shown greyed with
    /// a `~` prefix while the firm quote loads. NEVER feeds signing or validation
    /// — only the firm `quote` does. Returns nil when either price is missing or
    /// the input amount is non-positive, so the view can fall back to empty/0.
    static func toAmountIndicative(fromCoin: Coin, toCoin: Coin, fromAmount: String) -> Decimal? {
        let amount = fromAmount.toDecimal()
        guard amount > 0 else { return nil }

        let fromPrice = Decimal(fromCoin.price)
        let toPrice = Decimal(toCoin.price)
        guard fromPrice > 0, toPrice > 0 else { return nil }

        return amount * (fromPrice / toPrice)
    }

    static func inboundFeeDecimal(quote: SwapQuote?, toCoin: Coin) -> Decimal? {
        quote?.inboundFeeDecimal(toCoin: toCoin)
    }

    // MARK: - Branching predicates

    static func isApproveRequired(fromCoin: Coin, quote: SwapQuote?) -> Bool {
        fromCoin.shouldApprove && router(quote: quote) != nil
    }

    /// True iff this source swap settles via a Cosmos `MsgDeposit` on the swap
    /// chain itself rather than a cross-chain `MsgSend` to an Asgard vault.
    /// THORChain variants require a NATIVE source (RUNE) — the SDK rule
    /// `areEqualCoins(fromCoin, chainFeeCoin[swapChain])`, see
    /// `vultisig-sdk/packages/core/mpc/keysign/swap/build.ts`. MayaChain returns
    /// `true` unconditionally: Maya settles every source swap (native CACAO and
    /// non-native Maya assets alike) via `MsgDeposit`, matching the market path's
    /// long-standing behaviour.
    static func isDeposit(fromCoin: Coin) -> Bool {
        switch fromCoin.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return fromCoin.isNativeToken
        case .mayaChain:
            // MayaChain settles EVERY source swap via `MsgDeposit`, native CACAO
            // and non-native Maya assets alike — never a cross-chain `MsgSend`.
            // Keying this on `isNativeToken` (as the THORChain arm is) would flip
            // a non-native Maya market swap to an empty router so it can't sign.
            // Native THORChain limit deposits are gated separately in the
            // assembler (`thorchainChainPrefix == "THOR"`), so a Maya coin never
            // reaches the limit `MsgDeposit` branch regardless.
            return true
        default:
            return false
        }
    }

    // MARK: - Same-underlying secured mint

    /// True when the user holds an L1 asset and selected *its own* secured form
    /// (e.g. native BTC → secured BTC, or ERC20 USDC → secured USDC). Such a pair
    /// has no meaningful pool swap — it should mint via SECURE+ instead. The
    /// secured `toCoin`'s underlying is `<L1 chain>.<symbol>` (from its dash
    /// denom); `fromCoin.swapAsset` is the same `CHAIN.SYMBOL` form for the L1
    /// asset. `securedAssetSymbol` uppercases the hex contract while `swapAsset`
    /// preserves case, so the compare is case-insensitive.
    static func isSameUnderlyingSecuredMint(fromCoin: Coin, toCoin: Coin) -> Bool {
        guard THORChainHelper.isSecuredAsset(coin: toCoin) else { return false }
        let underlying = "\(THORChainHelper.securedAssetChain(coin: toCoin)).\(THORChainHelper.securedAssetSymbol(coin: toCoin))"
        return underlying.caseInsensitiveCompare(fromCoin.swapAsset) == .orderedSame
    }

    /// Synthetic display-only ~1:1 "Mint (SECURE+)" quote for the same-underlying
    /// case. The pool-quote fetch is skipped, so this fills the quote panel:
    /// `expectedAmountOut` is `fromAmount` in THORChain base units (so
    /// `toAmountDecimal ≈ fromAmount`), with no fees/slippage/memo. It NEVER feeds
    /// signing — the confirm path builds the real SECURE+ deposit payload; the
    /// minted amount settles on-chain at the current share ratio (~1:1 for these
    /// non-yield wrappers).
    static func securedMintQuote(fromAmount: Decimal, toCoin: Coin) -> SwapQuote {
        let expectedBase = fromAmount * toCoin.thorswapMultiplier
        let expectedAmountOut = NSDecimalNumber(decimal: expectedBase)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .down, scale: 0,
                raiseOnExactness: false, raiseOnOverflow: false,
                raiseOnUnderflow: false, raiseOnDivideByZero: false
            ))
            .stringValue
        return .thorchain(ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
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
        ))
    }

    // MARK: - Fee coin

    /// Native coin that pays for gas. For ERC20 sources we look up the EVM-native
    /// sibling in the fromCoins list; for native sources we return fromCoin directly.
    /// SwapTransaction precomputes this at hand-off so Verify/Done don't need
    /// fromCoins.
    static func feeCoin(fromCoin: Coin, fromCoins: [Coin]) -> Coin {
        guard !fromCoin.isNativeToken else { return fromCoin }
        return fromCoins.first { $0.chain == fromCoin.chain && $0.isNativeToken }
            ?? fromCoin
    }

    // MARK: - Default coin lookup (for chain switching)

    static func getDefaultCoin(for chain: Chain, vault: Vault) -> Coin? {
        let firstVaultCoin = vault.coins
            .filter { $0.chain == chain && $0.isNativeToken }
            .first

        if let firstVaultCoin {
            return firstVaultCoin
        }

        let coinMeta = TokensStore.TokenSelectionAssets
            .filter { $0.chain == chain }
            .sorted { $0.isNativeToken && !$1.isNativeToken }
            .first
        let pubKey = vault.chainPublicKeys.first { $0.chain == chain }?.publicKeyHex
        let isDerived = pubKey != nil
        guard let coinMeta,
              let coin = try? CoinFactory.create(
                asset: coinMeta,
                publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                hexChainCode: vault.hexChainCode,
                isDerived: isDerived,
                publicKeyMLDSA44: vault.publicKeyMLDSA44
              )
        else {
            return nil
        }
        return coin
    }

    // MARK: - Display: amounts

    static func fromFiatAmount(fromCoin: Coin, fromAmount: String) -> String {
        let fiatDecimal = fromCoin.fiat(decimal: fromAmountDecimal(fromAmount: fromAmount))
        return fiatDecimal.formatForDisplay()
    }

    static func toFiatAmount(toCoin: Coin, quote: SwapQuote?) -> String {
        let fiatDecimal = toCoin.fiat(decimal: toAmountDecimal(quote: quote, toCoin: toCoin))
        return fiatDecimal.formatForDisplay()
    }

    // MARK: - Display: fees

    /// Public list rate shown on swap fee surfaces. This is intentionally
    /// independent of the DEBUG-only wire affiliate configuration.
    static let affiliateListFeeBps = 50

    struct AffiliateDiscountBreakdown: Equatable {
        let vult: Decimal
        let referral: Decimal

        var total: Decimal { vult + referral }
    }

    static func showGas(gas: BigInt) -> Bool {
        !gas.isZero
    }

    static func showFees(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> Bool {
        let str = swapFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        return !str.isEmpty && !str.isZero
    }

    static func showTotalFees(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin, fee: BigInt) -> Bool {
        let str = totalFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: fee)
        return !str.isEmpty && !str.isZero
    }

    static func swapFeeString(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> String {
        if let evmFee = evmSwapFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin) {
            return evmFee.formatToFiat(includeCurrencySymbol: true)
        }

        guard let inboundFee = inboundFeeDecimal(quote: quote, toCoin: toCoin), !inboundFee.isZero else {
            return .empty
        }

        let inboundFeeRaw = toCoin.raw(for: inboundFee)
        return toCoin.fiat(value: inboundFeeRaw).formatToFiat(includeCurrencySymbol: true)
    }

    static func swapGasString(quote: SwapQuote?, feeCoin: Coin, gas: BigInt, fee: BigInt) -> String {
        // Quote-driven swaps: `fee` is the total network fee in the chain's
        // smallest unit (gasPrice × gasLimit for EVM). Format as a native amount
        // so the row reads "0.000861 ETH (~$2.00)" rather than a raw Gwei figure.
        // Guard against a non-native `feeCoin` to avoid formatting a wei-denominated
        // fee with an ERC20's decimals/ticker.
        if quote != nil {
            guard feeCoin.isNativeToken else { return .empty }
            let amount = feeCoin.decimal(for: fee)
            return "\(amount.formatToDecimal(digits: feeCoin.decimals).description) \(feeCoin.ticker)"
        }

        // No quote: `gas` is a gas price in wei for EVM chains, so display Gwei.
        if feeCoin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\((Decimal(gas) / weiPerGWeiDecimal).formatToDecimal(digits: 0).description) \(feeCoin.chain.feeUnit)"
        }

        let amount = feeCoin.decimal(for: gas)
        return "\(amount.formatToDecimal(digits: feeCoin.decimals).description) \(feeCoin.ticker)"
    }

    static func approveFeeString(feeCoin: Coin, fee: BigInt) -> String {
        feeCoin.fiat(gas: fee).formatToFiat(includeCurrencySymbol: true)
    }

    static func isApproveFeeZero(fee: BigInt) -> Bool {
        fee == .zero
    }

    /// Reconciled total fee = Network + Vultisig(affiliate) + Protocol(outbound),
    /// matching the itemized rows shown on the Verify/Details/Done screens.
    /// Deliberately NOT `fees.total`: that composite also carries the
    /// `asset`/liquidity slippage, which is already reflected in the quoted
    /// output amount and must not be double-counted (Android's reference,
    /// `SwapQuoteManager.kt`, reconciles the same way).
    static func totalFeeString(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin, fee: BigInt) -> String {
        guard quote != nil else { return .empty }
        let networkFee = feeCoin.fiat(gas: fee)
        let affiliateFee = affiliateFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        let outboundFee = outboundFeeFiat(quote: quote, toCoin: toCoin)
        return (networkFee + affiliateFee + outboundFee).formatToFiat(includeCurrencySymbol: true)
    }

    // MARK: - Display: limit-order network fee

    /// Network-fee crypto string for a LIMIT order — the source-chain broadcast
    /// gas already estimated into `fee` (in the fee coin's smallest units). A
    /// resting `=<` order has no market quote and no provider/inbound fee, so the
    /// shared quote-driven helpers (`fee` / `totalFeeString`) return `.zero` /
    /// `.empty` for it (`quote == nil`). Limit surfaces read this instead.
    /// Empty when no estimate is available yet.
    static func limitNetworkFeeString(feeCoin: Coin, fee: BigInt) -> String {
        guard fee > 0 else { return .empty }
        let amount = feeCoin.decimal(for: fee)
        return "\(amount.formatToDecimal(digits: feeCoin.decimals)) \(feeCoin.ticker)"
    }

    /// Fiat sub-line for the limit-order network fee. Mirrors the market network
    /// fee cell's fiat (`approveFeeString`). Empty when no estimate is available.
    static func limitNetworkFeeFiat(feeCoin: Coin, fee: BigInt) -> String {
        guard fee > 0 else { return .empty }
        return feeCoin.fiat(gas: fee).formatToFiat(includeCurrencySymbol: true)
    }

    // MARK: - Display: misc

    static func durationString(quote: SwapQuote?) -> String {
        guard let duration = quote?.totalSwapSeconds else { return "swap.duration.instant".localized }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.includesApproximationPhrase = false
        formatter.includesTimeRemainingPhrase = false
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        let fromDate = Date(timeIntervalSince1970: 0)
        let toDate = Date(timeIntervalSince1970: TimeInterval(duration))
        return formatter.string(from: fromDate, to: toDate) ?? .empty
    }

    /// Gross list-rate amount shown on the "Vultisig Fee" row. The quote
    /// exposes the net charged affiliate amount, so adding the exact displayed
    /// discounts reconstructs the undiscounted amount while `totalFeeString`
    /// deliberately remains net. SwapKit's affiliate is embedded in the quoted
    /// rate and therefore stays a note rather than a fabricated line-item value.
    static func baseAffiliateFee(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int,
        referralDiscountBps: Int
    ) -> String {
        guard let quote else { return .empty }
        if case .swapkit = quote {
            return "swap.included_in_rate".localized
        }
        let net = affiliateFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        let discounts = affiliateDiscountBreakdown(
            quote: quote,
            fromCoin: fromCoin,
            toCoin: toCoin,
            feeCoin: feeCoin,
            fromAmount: fromAmount,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
        return (net + discounts.total).formatToFiat(includeCurrencySymbol: true)
    }

    /// Whether the "Vultisig Fee" affiliate row should render. Every real market
    /// swap route has an affiliate concept (shown even at 0% for the Ultimate
    /// waiver), but a secured mint is a ~1:1 SECURE+ deposit with no affiliate
    /// and a limit order carries no market quote.
    ///
    /// The one exception is a Jupiter swap whose OUTPUT is native SOL: Jupiter
    /// collects the affiliate fee on the INPUT mint there (wrapped-SOL outputs
    /// have no fee ATA), so the amount is never surfaced in `toCoin` units
    /// (`feeOnInput == true`). Rather than render a misleading `$0.00` (the real
    /// fee is non-zero), the row is suppressed for that case, on both the form
    /// and verify (kept symmetric). A token-output Jupiter route always shows the
    /// row — including at 0.00% / $0.00 for the Ultimate tier, where the fee is
    /// on the output mint and simply zero.
    static func showAffiliateFeeRow(quote: SwapQuote?, mode: SwapMode) -> Bool {
        guard let quote, mode != .securedMint else { return false }
        if case let .jupiter(_, _, _, feeOnInput) = quote, feeOnInput {
            return false
        }
        return true
    }

    /// Affiliate (Vultisig) fee component in fiat — money Vultisig receives,
    /// itemized separately from the protocol's outbound/liquidity fees. The
    /// source per route: native THOR/Maya `fees.affiliate`, EVM aggregator
    /// `tx.swapFee`, LiFi (EVM `tx.swapFee`, Solana the integrator fraction of
    /// the output), Jupiter `platformFee`. SwapKit's flat affiliate is baked into
    /// the quoted rate (not a separable line item), so it contributes nothing to
    /// the itemized fiat total. `.zero` (not empty) for a real affiliate route
    /// charging 0 — the Ultimate/waiver case keeps a $0.00 row.
    static func affiliateFeeFiat(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> Decimal {
        guard let quote else { return .zero }
        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            let feeDecimal = q.fees.affiliate.toDecimal() / pow(10, 8)
            return toCoin.fiat(decimal: feeDecimal)
        case .oneinch, .kyberswap:
            let coin = swapFeeCoin(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
            let feeDecimal = coin.decimal(for: quote.evmSwapFeeBigInt ?? .zero)
            return coin.fiat(decimal: feeDecimal)
        case let .lifi(evmQuote, _, integratorFee):
            // EVM LiFi carries the fee as a token amount in `tx.swapFee`. Solana
            // LiFi deliberately reports `swapFee` "0" and charges the integrator
            // fee as a fraction of the output amount instead — so fall back to
            // that, or the fee row and Total would drop the charged fee.
            if let evmFee = quote.evmSwapFeeBigInt {
                let coin = swapFeeCoin(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
                return coin.fiat(decimal: coin.decimal(for: evmFee))
            }
            let outAmount = toCoin.decimal(for: BigInt(evmQuote.dstAmount) ?? .zero)
            return toCoin.fiat(decimal: outAmount * (integratorFee ?? 0))
        case let .jupiter(_, _, platformFee, _):
            // `platformFee` is already denominated in `toCoin` units (0 when the
            // fee is on the input mint or none is charged).
            return toCoin.fiat(decimal: platformFee)
        case .swapkit:
            return .zero
        }
    }

    /// List-rate label. Discounts are itemized separately and never reduce this
    /// percentage, regardless of the effective bps sent to a provider.
    static func swapFeeLabel(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        vultDiscountBps: Int
    ) -> String {
        guard quote != nil else { return "vultisigFee".localized }
        switch quote {
        case .oneinch, .kyberswap, .lifi, .jupiter:
            let net = affiliateFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
            if net <= 0, vultDiscountBps != Int.max {
                return "vultisigFee".localized
            }
        default:
            break
        }
        return String(format: "vultisigFeePercentage".localized, Double(affiliateListFeeBps) / 100.0)
    }

    /// Protocol outbound-fee component in fiat (denominated in the output asset),
    /// native THOR/Maya only. `.zero` for every other route. The `asset`/liquidity
    /// slippage component of `fees.total` is deliberately excluded — it is already
    /// reflected in the quoted output amount, so folding it into the fee total
    /// would double-count it.
    static func outboundFeeFiat(quote: SwapQuote?, toCoin: Coin) -> Decimal {
        guard let quote else { return .zero }
        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            return toCoin.fiat(decimal: q.fees.outbound.toDecimal() / pow(10, 8))
        default:
            return .zero
        }
    }

    static func outboundFeeString(quote: SwapQuote?, toCoin: Coin) -> String {
        guard let quote else { return .empty }
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return outboundFeeFiat(quote: quote, toCoin: toCoin).formatToFiat(includeCurrencySymbol: true)
        default:
            return .empty
        }
    }

    /// Whether the "Protocol Fee" (native outbound) row should render: a native
    /// THOR/Maya route carrying an outbound fee. Suppressed for a secured mint —
    /// its synthetic ~1:1 quote reports a zero outbound that is not a real
    /// protocol fee, so the row would otherwise show a spurious `$0.00`.
    static func showProtocolFeeRow(quote: SwapQuote?, toCoin: Coin, mode: SwapMode) -> Bool {
        guard mode != .securedMint else { return false }
        return !outboundFeeString(quote: quote, toCoin: toCoin).isEmpty
    }

    // MARK: - Discounts

    static func vultDiscountLabel(vultDiscountBps: Int) -> String {
        guard let tier = VultDiscountTier.from(bpsDiscount: vultDiscountBps) else {
            return "VULT: \(vultDiscountBps)%"
        }
        let percentage = tier == .ultimate ? 100 : tier.bpsDiscount
        return String(
            format: "swap.vult_discount".localized,
            tier.name.localized,
            percentage
        )
    }

    static func referralDiscountLabel(referralDiscountBps: Int) -> String {
        String(
            format: "swap.referral_discount".localized,
            SwapSlippage.format(bps: referralDiscountBps)
        )
    }

    static func vultDiscount(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int,
        referralDiscountBps: Int
    ) -> String {
        let breakdown = affiliateDiscountBreakdown(
            quote: quote,
            fromCoin: fromCoin,
            toCoin: toCoin,
            feeCoin: feeCoin,
            fromAmount: fromAmount,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
        return formatDiscount(breakdown.vult)
    }

    static func referralDiscount(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int,
        referralDiscountBps: Int
    ) -> String {
        let breakdown = affiliateDiscountBreakdown(
            quote: quote,
            fromCoin: fromCoin,
            toCoin: toCoin,
            feeCoin: feeCoin,
            fromAmount: fromAmount,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
        return formatDiscount(breakdown.referral)
    }

    static func affiliateDiscountBreakdown(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int,
        referralDiscountBps: Int
    ) -> AffiliateDiscountBreakdown {
        guard let quote else { return AffiliateDiscountBreakdown(vult: 0, referral: 0) }
        if case let .jupiter(_, _, _, feeOnInput) = quote, feeOnInput {
            return AffiliateDiscountBreakdown(vult: 0, referral: 0)
        }
        let inputFiat = fromCoin.fiat(decimal: fromAmountDecimal(fromAmount: fromAmount))
        guard inputFiat > 0 else { return AffiliateDiscountBreakdown(vult: 0, referral: 0) }

        let net = affiliateFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain, .swapkit:
            break
        default:
            guard net > 0 || vultDiscountBps == Int.max else {
                return AffiliateDiscountBreakdown(vult: 0, referral: 0)
            }
        }

        let appliesReferralDiscount: Bool
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            appliesReferralDiscount = true
        default:
            appliesReferralDiscount = false
        }

        let referral: Decimal
        if appliesReferralDiscount {
            let appliedBps = max(0, min(referralDiscountBps, affiliateListFeeBps))
            referral = inputFiat * Decimal(appliedBps) / 10000
        } else {
            referral = 0
        }

        let vult: Decimal
        if vultDiscountBps == Int.max {
            let listFee = inputFiat * Decimal(affiliateListFeeBps) / 10000
            vult = max(listFee - net - referral, 0)
        } else {
            let appliedBps = max(0, min(vultDiscountBps, affiliateListFeeBps))
            vult = inputFiat * Decimal(appliedBps) / 10000
        }

        return AffiliateDiscountBreakdown(vult: vult, referral: referral)
    }

    private static func formatDiscount(_ saving: Decimal) -> String {
        guard saving > 0 else { return .empty }
        if saving < 0.01 {
            return "-< " + "0.01".formatToFiat(includeCurrencySymbol: true)
        }
        return "-" + saving.formatToFiat(includeCurrencySymbol: true)
    }

    // MARK: - Price impact

    static func priceImpactString(quote: SwapQuote?) -> String {
        guard let impact = quote?.priceImpact else { return .empty }
        // THORChain returns positive slippage bps; we negate for consistent display.
        let displayImpact = -impact
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        guard let string = formatter.string(from: NSDecimalNumber(decimal: displayImpact)) else { return .empty }

        // Three-tier quality rating aligned with `priceImpactColor`'s bands so
        // the label and color always agree (Good / Average / High).
        if displayImpact > -0.01 {
            return "\(string) (\("swap.price_impact.good".localized))"
        } else if displayImpact > -0.03 {
            return "\(string) (\("swap.price_impact.average".localized))"
        } else {
            return "\(string) (\("swap.price_impact.high".localized))"
        }
    }

    static func priceImpactColor(quote: SwapQuote?) -> Color {
        guard let impact = quote?.priceImpact else { return Theme.colors.textSecondary }
        let displayImpact = -impact

        if displayImpact > -0.01 {
            return Theme.colors.alertSuccess
        } else if displayImpact > -0.03 {
            return Theme.colors.alertWarning
        } else {
            return Theme.colors.alertError
        }
    }

    // MARK: - Progress link

    static func progressLink(quote: SwapQuote?, fromCoin: Coin, hash: String) -> String? {
        ExplorerLinkBuilder.progressLink(quote: quote, txHash: hash, fromChain: fromCoin.chain)
    }

    // MARK: - Internal: EVM fee helpers

    private static func evmSwapFeeFiat(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> Decimal? {
        guard let swapFeeBigInt = quote?.evmSwapFeeBigInt else { return nil }
        let coin = swapFeeCoin(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        let feeDecimal = coin.decimal(for: swapFeeBigInt)
        let fiatValue = coin.fiat(decimal: feeDecimal)
        guard !fiatValue.isZero else { return nil }
        return fiatValue
    }

    /// Resolves the coin the quote's swap fee is denominated in. Also the
    /// source of truth for the coin context serialized onto the keysign
    /// payload — serializing this output guarantees the initiator's fiat
    /// display and the co-signer's agree by construction.
    static func swapFeeCoin(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> Coin {
        guard let contract = quote?.swapFeeTokenContract else {
            return feeCoin
        }
        if contract.caseInsensitiveCompare(fromCoin.contractAddress) == .orderedSame {
            return fromCoin
        }
        if contract.caseInsensitiveCompare(toCoin.contractAddress) == .orderedSame {
            return toCoin
        }
        return feeCoin
    }

    // MARK: - Validation

    /// Returns the specific balance error, or nil if balance is sufficient.
    /// Differentiates between insufficient token balance and insufficient gas.
    static func balanceError(fromCoin: Coin, feeCoin: Coin, fromAmount: String, fee: BigInt) -> Errors? {
        balanceError(fromCoin: fromCoin, feeCoin: feeCoin, amount: fromAmount.toDecimal(), fee: fee)
    }

    /// The same rule, entered with an amount that is already a `Decimal`.
    ///
    /// The limit form holds its sell amount as a `BigInt` in the source coin's
    /// base units, so routing it through the `String` entry point above would
    /// format it and immediately re-parse it through a locale-aware parser for
    /// nothing. Both swap tabs therefore share ONE affordability rule — there is
    /// no second implementation to drift.
    static func balanceError(fromCoin: Coin, feeCoin: Coin, amount: Decimal, fee: BigInt) -> Errors? {
        let fromFee = feeCoin.decimal(for: fee)
        let fromBalance = fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal

        if feeCoin == fromCoin {
            // Same coin pays for amount + gas.
            if fromFee + amount > fromBalance {
                // Amount alone fits but amount+fee doesn't ⇒ gas issue, not funds.
                if amount <= fromBalance, fromFee > 0 {
                    return .insufficientGas
                }
                return .insufficientFunds
            }
        } else {
            // Different coins: check gas token separately.
            if amount > fromBalance {
                return .insufficientFunds
            }
            if fromFee > feeCoinBalance {
                return .insufficientGas
            }
        }
        return nil
    }

    static func validateForm(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: String,
        quote: SwapQuote?,
        fee: BigInt,
        toAmount: Decimal,
        isSufficientBalance: Bool,
        isLoading: Bool
    ) -> Bool {
        fromCoin != toCoin
            && fromCoin != .example
            && toCoin != .example
            && !fromAmount.isEmpty
            && !toAmount.isZero
            && quote != nil
            && fee != .zero
            && isSufficientBalance
            && !isLoading
    }
}

// swiftlint:enable file_length
