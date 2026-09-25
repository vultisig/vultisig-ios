//
//  JoinKeysignReviewPresentation.swift
//  VultisigApp
//
//  Overview values for a joining signer. Every transaction field comes from
//  the received keysign payload, never from an initiator form or live quote.
//

import Foundation

enum JoinKeysignReviewPresentation {
    enum Surface: Equatable {
        case transactionReview(Kind)
        case session
    }

    enum Kind: Equatable, Identifiable {
        case send
        case swap
        case function

        var id: Self { self }

        var title: String {
            switch self {
            case .send: "sendOverview".localized
            case .swap: "swapOverview".localized
            case .function: "overview".localized
            }
        }
    }

    static func kind(for payload: KeysignPayload?) -> Kind? {
        guard let payload else { return nil }
        // A THORChain liquidity operation can carry swap metadata, but its
        // signed memo is an add/remove operation, not a swap.
        if liquidityDetails(for: payload) != nil { return .function }
        if payload.swapPayload != nil { return .swap }
        switch SignedTransactionDecoder.decode(payload).operation {
        case .transfer, .swap, .approve, .contractCall, .unknown:
            return .send
        default:
            return .function
        }
    }

    static func presentedKind(
        status: JoinKeysignStatus,
        payload: KeysignPayload?,
        hasCustomMessage: Bool
    ) -> Kind? {
        guard case .JoinKeysign = status, !hasCustomMessage else { return nil }
        return kind(for: payload)
    }

    static func surface(
        status: JoinKeysignStatus,
        payload: KeysignPayload?,
        hasCustomMessage: Bool
    ) -> Surface {
        if let kind = presentedKind(status: status, payload: payload, hasCustomMessage: hasCustomMessage) {
            return .transactionReview(kind)
        }
        return .session
    }

    static func newReviewKind(
        status: JoinKeysignStatus,
        payload: KeysignPayload?,
        hasCustomMessage: Bool,
        wasReviewStatus: Bool
    ) -> Kind? {
        guard !wasReviewStatus else { return nil }
        return presentedKind(status: status, payload: payload, hasCustomMessage: hasCustomMessage)
    }

    static func requiresRiskAcknowledgement(_ state: SecurityScannerState) -> Bool {
        guard let result = state.result else { return false }
        return !result.isSecure
    }

    @MainActor
    static func summary(
        for kind: Kind,
        viewModel: JoinKeysignViewModel
    ) -> KeysignReviewSummaryContent? {
        switch kind {
        case .send: .send(sendSummary(viewModel: viewModel))
        case .swap: swapSummary(viewModel: viewModel).map(KeysignReviewSummaryContent.swap)
        case .function: functionSummary(viewModel: viewModel).map(KeysignReviewSummaryContent.function)
        }
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
        var feeLines = [SwapReviewSummary.FeeLine(
            label: "networkFee".localized,
            value: Self.feeValue(networkFee)
        )]
        if let swapFee = viewModel.getSwapFee() {
            feeLines.append(.init(
                // The payload carries the charged affiliate amount, but not
                // the initiator's list-rate/discount provenance. Use its
                // unqualified Vultisig label rather than invent a percentage.
                label: "vultisigFee".localized,
                value: Self.feeValue(swapFee)
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
                chainLogo: swap.fromCoin.chainBadgeLogo,
                amount: fromAmount.formatForDisplay(),
                fiat: viewModel.getFromFiatAmount(),
                caption: nil,
                footnote: nil
            ),
            to: .init(
                logo: swap.toCoin.logo,
                ticker: swap.toCoin.ticker,
                chainLogo: swap.toCoin.chainBadgeLogo,
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

    @MainActor
    static func functionSummary(viewModel: JoinKeysignViewModel) -> FunctionTransactionReviewSummary? {
        guard let payload = viewModel.keysignPayload,
              kind(for: payload) == .function else { return nil }
        let details = liquidityDetails(for: payload)
        let decoded = SignedTransactionDecoder.decode(payload)
        let isStakingReview: Bool
        switch decoded.operation {
        case .stake, .unstake, .bond, .unbond, .rebond, .leave,
             .delegate, .undelegate, .redelegate, .claimRewards, .withdrawStake:
            isStakingReview = true
        default:
            isStakingReview = false
        }
        var rows: [FunctionTransactionReviewSummary.Row] = []
        if case .validator(let address) = decoded.counterparty {
            rows.append(.init(label: "validator".localized, value: address))
        } else if !isStakingReview, payload.toAddress.isNotEmpty {
            rows.append(.init(label: "to".localized, value: payload.toAddress))
        }
        if let details {
            for key in details.keys.sorted() {
                if let value = details[key] {
                    rows.append(.init(label: key.localized, value: value))
                }
            }
        } else if let memo = payload.memo, memo.isNotEmpty {
            rows.append(.init(label: "memo".localized, value: memo, isMultiline: true))
        }
        rows.append(.init(label: "network".localized, value: payload.coin.chain.name, image: payload.coin.chain.logo))
        let fees = viewModel.solanaAtaRentState == .loading
            ? (feeCrypto: "loading".localized, feeFiat: String.empty)
            : viewModel.getCalculatedNetworkFee()
        let hero = TransactionHeroResolver.hero(
            on: .keysignConfirm,
            for: .cosigning(payload: payload, simulated: { viewModel.verifyHeroContent })
        ) ?? .send(
            title: nil,
            coin: HeroCoinAmount(
                amount: liquidityAmount(for: payload, details: details),
                ticker: details == nil ? payload.coin.ticker : .empty,
                logo: payload.coin.logo
            )
        )
        let additionalRows = LimitOrderCancelPresentation.attachedDust(in: payload).map { dust in
            [FunctionTransactionReviewSummary.Row(
                label: "limitSwap.cancel.donatedDustRow".localized,
                value: "\(dust.amount) \(dust.ticker)"
            )]
        } ?? []
        return FunctionTransactionReviewSummary(
            hero: hero,
            vaultName: viewModel.vault.name,
            vaultAddress: payload.coin.address,
            rows: rows,
            fee: (fees.feeCrypto, fees.feeFiat),
            additionalRows: additionalRows
        )
    }

    private static func feeValue(_ fee: (feeCrypto: String, feeFiat: String)) -> String {
        guard fee.feeFiat.isNotEmpty else { return fee.feeCrypto }
        return "\(fee.feeCrypto) (\(fee.feeFiat))"
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
