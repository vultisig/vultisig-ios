//
//  JoinKeysignReviewPresentation.swift
//  VultisigApp
//
//  Overview values for a joining signer. Every transaction field comes from
//  the received keysign payload, never from an initiator form or live quote.
//

import Foundation

enum JoinKeysignReviewPresentation {
    enum Kind: Equatable, Identifiable {
        case send
        case swap

        var id: Self { self }
    }

    static func kind(for payload: KeysignPayload?) -> Kind? {
        guard let payload else { return nil }
        guard payload.swapPayload != nil else { return .send }
        // A THORChain liquidity operation can carry swap metadata, but its
        // signed memo is an add/remove operation, not a swap.
        if let memo = payload.memo, memo.starts(with: "+:") || memo.starts(with: "-:") {
            return .send
        }
        return .swap
    }

    static func presentedKind(
        status: JoinKeysignStatus,
        payload: KeysignPayload?,
        hasCustomMessage: Bool
    ) -> Kind? {
        guard case .JoinKeysign = status, !hasCustomMessage else { return nil }
        return kind(for: payload)
    }

    static func requiresRiskAcknowledgement(_ state: SecurityScannerState) -> Bool {
        guard let result = state.result else { return false }
        return !result.isSecure
    }

    @MainActor
    static func sendSummary(viewModel: JoinKeysignViewModel) -> SendCryptoVerifySummary {
        let payload = viewModel.keysignPayload
        let fees = viewModel.solanaAtaRentState == .loading
            ? (feeCrypto: "loading".localized, feeFiat: String.empty)
            : viewModel.getCalculatedNetworkFee()
        let lpDetails = liquidityDetails(for: payload)
        let isPlainRipplePayment = payload?.coin.chain == .ripple && payload?.swapPayload == nil
        let placement = LimitOrderPlacementPresentation.display(for: payload)
        var additionalRows: [SendCryptoVerifySummaryRow] = []
        if let placement {
            if let price = placement.targetPriceValue {
                additionalRows.append(.init(title: "limitSwap.detail.target", value: price))
            }
            additionalRows.append(.init(title: "limitSwap.expiry", value: placement.expiryValue))
        } else if let dust = LimitOrderCancelPresentation.attachedDust(in: payload) {
            additionalRows.append(.init(
                title: "limitSwap.cancel.donatedDustRow",
                value: "\(dust.amount) \(dust.ticker)"
            ))
        }

        return SendCryptoVerifySummary(
            fromName: viewModel.vault.name,
            fromAddress: payload?.coin.address ?? .empty,
            toAddress: payload?.toAddress ?? .empty,
            network: payload?.coin.chain.name ?? .empty,
            networkImage: payload?.coin.chain.logo ?? .empty,
            memo: isPlainRipplePayment
                ? (payload.flatMap { RippleDestinationTag.displayMemo(for: $0) } ?? .empty)
                : (viewModel.memo ?? .empty),
            destinationTag: payload.flatMap { RippleDestinationTag.displayTag(for: $0) }.map(String.init),
            decodedFunctionSignature: viewModel.decodedFunctionSignature,
            decodedFunctionArguments: viewModel.decodedFunctionArguments,
            memoFunctionDictionary: lpDetails,
            feeCrypto: fees.feeCrypto,
            feeFiat: fees.feeFiat,
            isCalculatingFee: viewModel.solanaAtaRentState == .loading,
            coinImage: payload?.coin.logo ?? .empty,
            amount: liquidityAmount(for: payload, details: lpDetails),
            amountFiat: lpDetails == nil ? viewModel.getAmountFiat() : .empty,
            coinTicker: payload?.coin.ticker ?? .empty,
            keysignPayload: payload,
            hero: TransactionHeroResolver.hero(
                on: .keysignConfirm,
                for: .cosigning(payload: payload, simulated: { viewModel.verifyHeroContent })
            ),
            tokenDisplay: viewModel.decodedTokenDisplay,
            tokenDisplayIsUnlimited: viewModel.decodedTokenIsUnlimited,
            vault: viewModel.vault,
            dappMetadata: viewModel.dappMetadata,
            additionalRows: additionalRows
        )
    }

    @MainActor
    static func swapSummary(viewModel: JoinKeysignViewModel) -> SwapReviewSummary? {
        guard let payload = viewModel.keysignPayload,
              let swap = payload.swapPayload,
              kind(for: payload) == .swap else { return nil }

        let fromAmount = swap.fromCoin.decimal(for: swap.fromAmount)
        let toAmount = swap.toAmountDecimal
        let networkFee = viewModel.solanaAtaRentState == .loading
            ? (feeCrypto: "loading".localized, feeFiat: String.empty)
            : viewModel.getCalculatedNetworkFee()
        var feeLines = [
            SwapReviewSummary.FeeLine(
                label: viewModel.swapFeeLabelKeys.networkFee.localized,
                value: "\(networkFee.feeCrypto) \(networkFee.feeFiat)"
            )
        ]
        if let swapFee = viewModel.getSwapFee() {
            feeLines.append(.init(
                label: "swapFee".localized,
                value: "\(swapFee.feeCrypto) \(swapFee.feeFiat)"
            ))
        }
        if !viewModel.priceImpactString.isEmpty {
            feeLines.append(.init(
                label: "swap.price_impact".localized,
                value: viewModel.priceImpactString,
                valueColor: viewModel.priceImpactColor
            ))
        }

        return SwapReviewSummary(
            from: .init(
                logo: swap.fromCoin.logo,
                ticker: swap.fromCoin.ticker,
                chainLogo: chainBadge(for: swap.fromCoin),
                amount: fromAmount.formatForDisplay(),
                fiat: viewModel.getFromFiatAmount(),
                caption: nil,
                footnote: nil
            ),
            to: .init(
                logo: swap.toCoin.logo,
                ticker: swap.toCoin.ticker,
                chainLogo: chainBadge(for: swap.toCoin),
                amount: toAmount.formatForDisplay(),
                fiat: viewModel.getToFiatAmount(),
                caption: viewModel.toAmountCaptionKey.localized,
                footnote: viewModel.getMinPayoutCaption()
            ),
            vaultName: viewModel.vault.name,
            vaultAddress: payload.coin.address,
            limitTerms: nil,
            provider: (name: swap.providerDisplayName, logo: swap.providerName),
            slippage: nil,
            totalFee: viewModel.getSwapTotalFee(),
            feeLines: feeLines,
            limitNetworkFee: nil,
            externalRecipient: payload.swapExternalRecipient
        )
    }

    private static func chainBadge(for coin: Coin) -> String? {
        coin.logo == coin.chain.logo ? nil : coin.chain.logo
    }

    private static func liquidityDetails(for payload: KeysignPayload?) -> [String: String]? {
        guard let memo = payload?.memo, !memo.isEmpty else { return nil }
        let parts = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let prefix = parts.first else { return nil }
        switch prefix {
        case "+":
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            var details = ["pool": parts[1], "memo": memo]
            if parts.count >= 3, !parts[2].isEmpty { details["pairedAddress"] = parts[2] }
            return details
        case "-":
            guard parts.count >= 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
            var details = ["pool": parts[1], "memo": memo]
            if let basisPoints = Int(parts[2]) {
                details["withdrawPercentage"] = "\(Double(basisPoints) / 100)%"
            }
            return details
        default:
            return nil
        }
    }

    private static func liquidityAmount(for payload: KeysignPayload?, details: [String: String]?) -> String {
        let amount = payload?.toAmountString ?? .empty
        guard let payload, let pool = details?["pool"], !pool.isEmpty else { return amount }
        return "\(amount) \(payload.coin.ticker) → \(ThorchainService.cleanPoolName(pool)) LP"
    }
}
