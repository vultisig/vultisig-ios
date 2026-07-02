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

    enum Errors: String, Error, LocalizedError {
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
        fromCoin.raw(for: fromAmount.toDecimal())
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
        case let .jupiter(_, fee, _):
            // Jupiter exposes no network fee at quote time; fall back to the
            // Solana-source plan fee carried in `thorchainFee`
            // (`chainSpecific.gas`), the same way Send computes it.
            return fee ?? thorchainFee
        case nil:
            return .zero
        }
    }

    // MARK: - EVM signed network fee (shared with the co-signer)

    /// EVM swap network fee valued at the gas the transaction is actually signed
    /// with: the conservative EIP-1559 ceiling (`maxFeePerGas`) times
    /// `max(routeGas, gasLimit)`, where an aggregator route gas beats the
    /// native-ETH gas floor. Shared by the initiator's fee display and the
    /// co-signer (`JoinKeysignGasViewModel`) so both devices show the same
    /// number. Display-only — never feeds the insufficient-gas gate.
    static func evmSignedSwapNetworkFeeWei(maxFeePerGasWei: BigInt, routeGas: BigInt, gasLimit: BigInt) -> BigInt {
        maxFeePerGasWei * max(routeGas, gasLimit)
    }

    /// Network fee value the initiator shows on the swap verify/done screens. For
    /// EVM aggregator swaps it's the signed-gas fee (`maxFeePerGas ×
    /// max(routeGas, gasLimit)`) so the initiator matches the co-signer; `gas`
    /// carries `maxFeePerGas` for EVM. The initiator doesn't retain the stored
    /// gas floor at display time, so `routeGas` (the signed gas for aggregator
    /// routes) stands in for `gasLimit`. Everything else — native-protocol swaps,
    /// or before the EIP-1559 fee has loaded — keeps the existing quote fee.
    /// Display-only: the insufficient-gas validation keeps using `fee`.
    static func displayedSwapNetworkFeeWei(quote: SwapQuote?, feeCoin: Coin, gas: BigInt, fee: BigInt) -> BigInt {
        guard feeCoin.chain.chainType == .EVM, gas > 0, let routeGas = quote?.evmRouteGas else {
            return fee
        }
        return evmSignedSwapNetworkFeeWei(maxFeePerGasWei: gas, routeGas: routeGas, gasLimit: routeGas)
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
        case let .jupiter(quote, _, _):
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

    static func isDeposit(fromCoin: Coin) -> Bool {
        fromCoin.chain == .mayaChain
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

    static func totalFeeString(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin, fee: BigInt) -> String {
        let networkFee = feeCoin.fiat(gas: fee)

        if let evmFee = evmSwapFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin) {
            return (evmFee + networkFee).formatToFiat(includeCurrencySymbol: true)
        }

        guard let inboundFee = inboundFeeDecimal(quote: quote, toCoin: toCoin) else { return .empty }

        let inboundFeeRaw = toCoin.raw(for: inboundFee)
        let providerFee = toCoin.fiat(value: inboundFeeRaw)
        return (providerFee + networkFee).formatToFiat(includeCurrencySymbol: true)
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

    static func baseAffiliateFee(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin) -> String {
        guard let quote else { return .empty }

        if let evmFee = evmSwapFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin) {
            return evmFee.formatToFiat(includeCurrencySymbol: true)
        }

        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            let feeAmount = q.fees.affiliate.toDecimal()
            guard feeAmount > 0 else { return .empty }
            let feeDecimal = feeAmount / pow(10, 8)
            return toCoin.fiat(decimal: feeDecimal).formatToFiat(includeCurrencySymbol: true)
        default:
            return .empty
        }
    }

    static func swapFeeLabel(quote: SwapQuote?, fromCoin: Coin, toCoin: Coin, feeCoin: Coin, fromAmount: String) -> String {
        guard let quote else { return "swapFee".localized }

        let feeFiat: Decimal
        if let evmFee = evmSwapFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin) {
            feeFiat = evmFee
        } else {
            switch quote {
            case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
                let feeAmt = q.fees.affiliate.toDecimal() / pow(10, 8)
                feeFiat = toCoin.fiat(decimal: feeAmt)
            default:
                return String(format: "swapFeePercentage".localized, 0.0)
            }
        }

        let inputFiat = fromCoin.fiat(decimal: fromAmountDecimal(fromAmount: fromAmount))
        guard inputFiat > 0 else { return "swapFee".localized }

        let percentage = (feeFiat / inputFiat) * 100
        return String(format: "swapFeePercentage".localized, NSDecimalNumber(decimal: percentage).doubleValue)
    }

    static func outboundFeeString(quote: SwapQuote?, toCoin: Coin) -> String {
        guard let quote else { return .empty }

        var outboundFeeString: String?
        let feeDecimals = 8 // THORChain standard

        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }

        guard let outboundFeeString else { return .empty }
        let feeAmount = outboundFeeString.toDecimal()
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        // Outbound fee is denominated in the output asset.
        return toCoin.fiat(decimal: feeDecimal).formatToFiat(includeCurrencySymbol: true)
    }

    // MARK: - Discounts

    static func vultDiscountLabel(vultDiscountBps: Int) -> String {
        if vultDiscountBps == Int.max {
            return "swap.vult_waiver".localized
        }
        return String(format: "swap.vult_discount".localized, vultDiscountBps)
    }

    static func referralDiscountLabel(referralDiscountBps: Int) -> String {
        String(format: "swap.referral_discount".localized, referralDiscountBps)
    }

    static func vultDiscount(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int
    ) -> String {
        getDiscountString(
            quote: quote,
            fromCoin: fromCoin,
            toCoin: toCoin,
            feeCoin: feeCoin,
            fromAmount: fromAmount,
            vultDiscountBps: vultDiscountBps,
            shareBps: vultDiscountBps
        )
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
        getDiscountString(
            quote: quote,
            fromCoin: fromCoin,
            toCoin: toCoin,
            feeCoin: feeCoin,
            fromAmount: fromAmount,
            vultDiscountBps: vultDiscountBps,
            shareBps: referralDiscountBps
        )
    }

    private static func getDiscountString(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String,
        vultDiscountBps: Int,
        shareBps: Int
    ) -> String {
        guard shareBps > 0 else { return .empty }

        // Ultimate tier (Int.max) ⇒ 100% waiver, return total saving.
        if shareBps == Int.max {
            let totalSaving = calculateTotalSaving(
                quote: quote,
                fromCoin: fromCoin,
                toCoin: toCoin,
                feeCoin: feeCoin,
                fromAmount: fromAmount
            )
            guard totalSaving > 0 else { return .empty }
            return "-" + totalSaving.formatToFiat(includeCurrencySymbol: true)
        }

        // Referral discount not applicable when Ultimate VULT tier
        if vultDiscountBps == Int.max {
            return .empty
        }

        let inputFiat = fromCoin.fiat(decimal: fromAmountDecimal(fromAmount: fromAmount))
        let saving = inputFiat * Decimal(shareBps) / 10000

        guard saving > 0 else { return .empty }

        if saving < 0.01 {
            return "-< " + "0.01".formatToFiat(includeCurrencySymbol: true)
        }

        return "-" + saving.formatToFiat(includeCurrencySymbol: true)
    }

    private static func calculateTotalSaving(
        quote: SwapQuote?,
        fromCoin: Coin,
        toCoin: Coin,
        feeCoin: Coin,
        fromAmount: String
    ) -> Decimal {
        let inputFiat = fromCoin.fiat(decimal: fromAmountDecimal(fromAmount: fromAmount))

        // Theoretical Base Fee (0.50%)
        let baseFeeFiat = inputFiat * 0.0050

        // Actual fee from quote
        var actualFeeFiat = evmSwapFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin) ?? 0
        if actualFeeFiat == 0, let quote {
            switch quote {
            case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
                let feeAmt = q.fees.affiliate.toDecimal() / pow(10, 8)
                actualFeeFiat = toCoin.fiat(decimal: feeAmt)
            default: break
            }
        }

        return max(baseFeeFiat - actualFeeFiat, 0)
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
        let fromFee = feeCoin.decimal(for: fee)
        let fromBalance = fromCoin.balanceDecimal
        let feeCoinBalance = feeCoin.balanceDecimal
        let amount = fromAmount.toDecimal()

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

    static func isSufficientBalance(fromCoin: Coin, feeCoin: Coin, fromAmount: String, fee: BigInt) -> Bool {
        balanceError(fromCoin: fromCoin, feeCoin: feeCoin, fromAmount: fromAmount, fee: fee) == nil
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
