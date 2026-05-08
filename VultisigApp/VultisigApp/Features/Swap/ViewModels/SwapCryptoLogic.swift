//
//  SwapCryptoLogic.swift
//  VultisigApp
//
//  Created by Vultisig on 2025-02-03.
//

import BigInt
import Mediator
import SwiftUI
import WalletCore

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
            case .unexpectedError:
                return "swapErrorUnexpectedTitle".localized
            case .insufficientFunds:
                return "swapErrorInsufficientFundsTitle".localized
            case .insufficientGas:
                return "swapErrorInsufficientGasTitle".localized
            case .swapAmountTooSmall:
                return "swapErrorAmountTooSmallTitle".localized
            case .inboundAddress:
                return "swapErrorInboundAddressTitle".localized
            case .sameAsset:
                return "swapErrorSameAssetTitle".localized
            }
        }

        var errorDescription: String? {
            switch self {
            case .unexpectedError:
                return "swapErrorUnexpectedDescription".localized
            case .insufficientFunds:
                return "swapErrorInsufficientFundsDescription".localized
            case .insufficientGas:
                return "swapErrorInsufficientGasDescription".localized
            case .swapAmountTooSmall:
                return "swapErrorAmountTooSmallDescription".localized
            case .inboundAddress:
                return "swapErrorInboundAddressDescription".localized
            case .sameAsset:
                return "swapErrorSameAssetDescription".localized
            }
        }
    }

    // MARK: - Formatters & Presentation

    static func progressLink(draft: SwapDraft, hash: String) -> String? {
        ExplorerLinkBuilder.progressLink(quote: draft.quote, txHash: hash, fromChain: draft.fromCoin.chain)
    }

    static func fromFiatAmount(draft: SwapDraft) -> String {
        let fiatDecimal = draft.fromCoin.fiat(decimal: Self.fromAmountDecimal(draft: draft))
        return fiatDecimal.formatForDisplay()
    }

    static func toFiatAmount(draft: SwapDraft) -> String {
        let fiatDecimal = draft.toCoin.fiat(decimal: Self.toAmountDecimal(draft: draft))
        return fiatDecimal.formatForDisplay()
    }

    static func showGas(draft: SwapDraft) -> Bool {
        return !draft.gas.isZero
    }

    static func showFees(draft: SwapDraft) -> Bool {
        let fee = swapFeeString(draft: draft)
        return !fee.isEmpty && !fee.isZero
    }

    static func showTotalFees(draft: SwapDraft) -> Bool {
        let fee = totalFeeString(draft: draft)
        return !fee.isEmpty && !fee.isZero
    }

    static func showDuration(draft: SwapDraft) -> Bool {
        return showFees(draft: draft)
    }

    static func showAllowance(draft: SwapDraft) -> Bool {
        return Self.isApproveRequired(draft: draft)
    }

    static func showToAmount(draft: SwapDraft) -> Bool {
        return Self.toAmountDecimal(draft: draft) != 0
    }

    static func swapFeeString(draft: SwapDraft) -> String {
        if let evmFee = evmSwapFeeFiat(draft: draft) {
            return evmFee.formatToFiat(includeCurrencySymbol: true)
        }

        guard let inboundFeeDecimal = Self.inboundFeeDecimal(draft: draft), !inboundFeeDecimal.isZero else { return .empty }

        let inboundFee = draft.toCoin.raw(for: inboundFeeDecimal)
        let fee = draft.toCoin.fiat(value: inboundFee)
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    static func swapGasString(draft: SwapDraft) -> String {
        let coin = feeCoin(draft: draft)
        let decimals = coin.decimals

        // Use Self.fee(draft: draft) for swap quotes (which includes corrected gas price calculations)
        // Fall back to draft.gas for other transaction types
        let gasValue = draft.quote != nil ? Self.fee(draft: draft) : draft.gas

        if coin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\((Decimal(gasValue) / weiPerGWeiDecimal).formatToDecimal(digits: 0).description) \(coin.chain.feeUnit)"
        } else {
            return "\((Decimal(gasValue) / pow(10, decimals)).formatToDecimal(digits: decimals).description) \(coin.ticker)"
        }
    }

    static func approveFeeString(draft: SwapDraft) -> String {
        let fromCoin = feeCoin(draft: draft)
        let fee = fromCoin.fiat(gas: Self.fee(draft: draft))
        return fee.formatToFiat(includeCurrencySymbol: true)
    }

    static func isApproveFeeZero(draft: SwapDraft) -> Bool {
        return Self.fee(draft: draft) == .zero
    }

    static func totalFeeString(draft: SwapDraft) -> String {
        let fromCoin = feeCoin(draft: draft)
        let networkFee = fromCoin.fiat(gas: Self.fee(draft: draft))

        if let evmFee = evmSwapFeeFiat(draft: draft) {
            let totalFee = evmFee + networkFee
            return totalFee.formatToFiat(includeCurrencySymbol: true)
        }

        guard let inboundFeeDecimal = Self.inboundFeeDecimal(draft: draft) else { return .empty }

        let inboundFee = draft.toCoin.raw(for: inboundFeeDecimal)
        let providerFee = draft.toCoin.fiat(value: inboundFee)
        let totalFee = providerFee + networkFee
        return totalFee.formatToFiat(includeCurrencySymbol: true)
    }

    static func durationString(draft: SwapDraft) -> String {
        guard let duration = draft.quote?.totalSwapSeconds else { return "swap.duration.instant".localized }
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

    static func baseAffiliateFee(draft: SwapDraft) -> String {
        guard let quote = draft.quote else { return .empty }

        if let evmFee = evmSwapFeeFiat(draft: draft) {
            return evmFee.formatToFiat(includeCurrencySymbol: true)
        }

        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            let feeAmount = q.fees.affiliate.toDecimal()
            guard feeAmount > 0 else { return .empty }
            let feeDecimal = feeAmount / pow(10, 8)
            let fiatValue = draft.toCoin.fiat(decimal: feeDecimal)
            return fiatValue.formatToFiat(includeCurrencySymbol: true)
        default:
            return .empty
        }
    }

    static func swapFeeLabel(draft: SwapDraft) -> String {
        // Calculate effective BPS from the quote vs input?
        // Or simply display the theoretical BPS if we can't reverse math it easily due to price fluctuations?
        // Agent Rule: "Percentage (from quote)"
        // ThorchainQuote doesn't have "affiliate_bps" field explicitly in the struct we saw?
        // Struct: `slippageBps`.
        // If not present, we can calculate: (AffiliateFeeFiat / InputFiat) * 10000

        guard let quote = draft.quote else { return "swapFee".localized }

        let feeFiat: Decimal
        if let evmFee = evmSwapFeeFiat(draft: draft) {
            feeFiat = evmFee
        } else {
            switch quote {
            case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
                let feeAmt = q.fees.affiliate.toDecimal() / pow(10, 8)
                feeFiat = draft.toCoin.fiat(decimal: feeAmt)
            default:
                return String(format: "swapFeePercentage".localized, 0.0)
            }
        }

        let inputFiat = draft.fromCoin.fiat(decimal: Self.fromAmountDecimal(draft: draft))
        guard inputFiat > 0 else { return "swapFee".localized }

        let percentage = (feeFiat / inputFiat) * 100
        return String(format: "swapFeePercentage".localized, NSDecimalNumber(decimal: percentage).doubleValue)
    }

    static func outboundFeeString(draft: SwapDraft) -> String {
        guard let quote = draft.quote else { return .empty }

        var outboundFeeString: String?
        let feeDecimals = 8 // Default to 8 (THORChain standard)
        let feeCoin: Coin = draft.toCoin // Outbound fee is in output asset

        switch quote {
        case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }

        guard let outboundFeeString = outboundFeeString else {
            return .empty
        }
        let feeAmount = outboundFeeString.toDecimal()

        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)

        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }

    static func vultDiscountLabel(draft: SwapDraft) -> String {
        if draft.vultDiscountBps == Int.max {
            return "swap.vult_waiver".localized
        }
        return String(format: "swap.vult_discount".localized, draft.vultDiscountBps)
    }

    static func referralDiscountLabel(draft: SwapDraft) -> String {
        return String(format: "swap.referral_discount".localized, draft.referralDiscountBps)
    }

    static func vultDiscount(draft: SwapDraft) -> String {
        return getDiscountString(draft: draft, shareBps: draft.vultDiscountBps)
    }

    static func referralDiscount(draft: SwapDraft) -> String {
        return getDiscountString(draft: draft, shareBps: draft.referralDiscountBps)
    }

    private static func getDiscountString(draft: SwapDraft, shareBps: Int) -> String {
        guard shareBps > 0 else { return .empty }

        // Handle Ultimate tier (Int.max) - they get 100% waiver
        if shareBps == Int.max {
            let totalSaving = calculateTotalSaving(draft: draft)
            guard totalSaving > 0 else { return .empty }
            let formattedCcy = totalSaving.formatToFiat(includeCurrencySymbol: true)
            return "-" + formattedCcy
        }

        // Referral discount not applicable when Ultimate VULT tier
        if draft.vultDiscountBps == Int.max {
            return .empty
        }

        let inputFiat = draft.fromCoin.fiat(decimal: Self.fromAmountDecimal(draft: draft))
        let saving = inputFiat * Decimal(shareBps) / 10000

        guard saving > 0 else { return .empty }

        if saving < 0.01 {
            return "-< " + "0.01".formatToFiat(includeCurrencySymbol: true)
        }

        let formattedCcy = saving.formatToFiat(includeCurrencySymbol: true)
        return "-" + formattedCcy
    }

    private static func calculateTotalSaving(draft: SwapDraft) -> Decimal {
        let inputFiat = draft.fromCoin.fiat(decimal: Self.fromAmountDecimal(draft: draft))

        // Theoretical Base Fee (0.50%)
        let baseFeeFiat = inputFiat * 0.0050

        // Actual Fee from Quote
        var actualFeeFiat = evmSwapFeeFiat(draft: draft) ?? 0
        if actualFeeFiat == 0, let quote = draft.quote {
            switch quote {
            case let .thorchain(q), let .thorchainChainnet(q), let .thorchainStagenet(q), let .mayachain(q):
                let feeAmt = q.fees.affiliate.toDecimal() / pow(10, 8)
                actualFeeFiat = draft.toCoin.fiat(decimal: feeAmt)
            default: break
            }
        }

        // Total Saving
        return max(baseFeeFiat - actualFeeFiat, 0)
    }

    // MARK: - Price Impact

    static func priceImpactString(draft: SwapDraft) -> String {
        guard let impact = draft.quote?.priceImpact else { return .empty }
        // Price impact is usually negative (cost), but THORChain returns positive slippage bps.
        // We negate it for consistent display (e.g. -0.19%).
        let displayImpact = -impact
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        // .percent style expects fractional value (0.01 = 1%), don't multiply by 100
        guard let string = formatter.string(from: NSDecimalNumber(decimal: displayImpact)) else { return .empty }

        if displayImpact > -0.01 { // Less than 1% slippage is usually considered "Good" or "Neutral"
            return "\(string) (\("swap.price_impact.good".localized))"
        } else {
            return "\(string) (\("swap.price_impact.high".localized))"
        }
    }

    static func priceImpactColor(draft: SwapDraft) -> Color {
        guard let impact = draft.quote?.priceImpact else { return Theme.colors.textSecondary }
        let displayImpact = -impact

        if displayImpact > -0.01 {
            return Theme.colors.alertSuccess
        } else if displayImpact > -0.03 {
            return Theme.colors.alertWarning
        } else {
            return Theme.colors.alertError
        }
    }

    // MARK: - Helper Logic

    private static func evmSwapFeeFiat(draft: SwapDraft) -> Decimal? {
        guard let swapFeeBigInt = draft.quote?.evmSwapFeeBigInt else { return nil }
        let coin = swapFeeCoin(draft: draft)
        let feeDecimal = coin.decimal(for: swapFeeBigInt)
        let fiatValue = coin.fiat(decimal: feeDecimal)
        guard !fiatValue.isZero else { return nil }
        return fiatValue
    }

    private static func swapFeeCoin(draft: SwapDraft) -> Coin {
        guard let contract = draft.quote?.swapFeeTokenContract else {
            return feeCoin(draft: draft)
        }
        if contract.caseInsensitiveCompare(draft.fromCoin.contractAddress) == .orderedSame {
            return draft.fromCoin
        }
        if contract.caseInsensitiveCompare(draft.toCoin.contractAddress) == .orderedSame {
            return draft.toCoin
        }
        return feeCoin(draft: draft)
    }

    static func getDefaultCoin(for chain: Chain, vault: Vault) -> Coin? {
        let firstVaultCoin = vault.coins
            .filter { $0.chain == chain && $0.isNativeToken }
            .first

        if let firstVaultCoin {
            return firstVaultCoin
        } else {
            let coinMeta = TokensStore.TokenSelectionAssets
                .filter { $0.chain == chain }
                .sorted { $0.isNativeToken && !$1.isNativeToken }
                .first
            let pubKey = vault.chainPublicKeys.first { $0.chain == chain }?.publicKeyHex
            let isDerived = pubKey != nil
            guard let coinMeta, let coin = try? CoinFactory.create(asset: coinMeta,
                                                                   publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                                                                   publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                                                                   hexChainCode: vault.hexChainCode,
                                                                   isDerived: isDerived,
                                                                   publicKeyMLDSA44: vault.publicKeyMLDSA44)
            else {
                return nil
            }
            return coin
        }
    }

    static func pickerFromCoins(draft: SwapDraft, fromChain: Chain?) -> [Coin] {
        return draft.fromCoins.filter { coin in
            coin.chain == fromChain
        }.sorted(by: {
            Int($0.chain == draft.fromCoin.chain) > Int($1.chain == draft.fromCoin.chain)
        })
    }

    static func pickerToCoins(draft: SwapDraft, toChain: Chain?) -> [Coin] {
        return draft.toCoins.filter { coin in
            coin.chain == toChain
        }.sorted(by: {
            Int($0.chain == draft.toCoin.chain) > Int($1.chain == draft.toCoin.chain)
        })
    }

}
