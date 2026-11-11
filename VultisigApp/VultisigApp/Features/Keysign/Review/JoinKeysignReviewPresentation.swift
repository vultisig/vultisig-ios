//
//  JoinKeysignReviewPresentation.swift
//  VultisigApp
//
//  Overview values for a joining signer. Every transaction field comes from
//  the received keysign payload, never from an initiator form or live quote.
//

import Foundation
import WalletCore

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
        let hasSignedBody = payload?.hasSignedCosmosBody == true
        let signedTransfer = payload.flatMap(Self.signedTransfer)
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
            toAddress: signedTransfer.map(\.recipient) ?? (hasSignedBody ? .empty : payload?.toAddress ?? .empty),
            network: payload?.coin.chain.displayName ?? .empty,
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
            amount: hasSignedBody
                ? (signedTransfer?.amount.formatForDisplay() ?? .empty)
                : liquidityAmount(for: payload, details: lpDetails),
            amountFiat: lpDetails == nil && !hasSignedBody ? viewModel.getAmountFiat() : .empty,
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
            externalRecipient: payload.swapExternalRecipient,
            depositRecipient: .success(viewModel.swapKitDepositRecipient)
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
        let ballot = decoded.operation == .vote
            ? payload.signDirect.flatMap { CosmosSignDocReader.ballot(bodyBytes: $0.bodyBytes) }
            : nil
        if let ballot {
            rows.append(.init(label: "proposalID".localized, value: String(ballot.proposalID)))
            rows.append(.init(label: "governanceVoteAction".localized, value: voteTitle(ballot.option)))
        } else if case .validator(let address) = decoded.counterparty {
            rows.append(.init(label: "validator".localized, value: address))
        } else if let transfer = signedTransfer(of: payload) {
            rows.append(.init(label: "to".localized, value: transfer.recipient))
        } else if !isStakingReview, !payload.hasSignedCosmosBody, payload.toAddress.isNotEmpty {
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
        rows.append(.init(label: "network".localized, value: payload.coin.chain.displayName, image: payload.coin.chain.logo))
        let fees = viewModel.solanaAtaRentState == .loading
            ? (feeCrypto: "loading".localized, feeFiat: String.empty)
            : viewModel.getCalculatedNetworkFee()
        let hero = TransactionHeroResolver.hero(
            on: .keysignConfirm,
            for: .cosigning(payload: payload, simulated: { viewModel.verifyHeroContent })
        ) ?? ballot.map { .title(text: "governanceVoteAction".localized, caption: voteTitle($0.option)) } ?? .send(
            title: nil,
            coin: HeroCoinAmount(
                amount: !payload.hasSignedCosmosBody
                    ? liquidityAmount(for: payload, details: details)
                    : (signedTransfer(of: payload)?.amount.formatForDisplay() ?? .empty),
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

    /// Recipient and amount of a single Cosmos send, read from the signed
    /// `signDirect` body or `signAmino` messages rather than the initiator's
    /// display copy. Nil for anything else, or when the denom is not the
    /// payload coin's own.
    static func signedTransfer(of payload: KeysignPayload) -> (recipient: String, amount: Decimal)? {
        let send: (recipient: String, denom: String, raw: String)?
        if let direct = payload.signDirect {
            guard let reading = CosmosSignDocReader.read(bodyBytes: direct.bodyBytes),
                  reading.operation == .transfer,
                  case .contract(let recipient)? = reading.counterparty,
                  case .units(let raw, .denom(let denom)) = reading.amount
            else { return nil }
            send = (recipient, denom, raw.description)
        } else if let amino = payload.signAmino {
            send = aminoSend(amino)
        } else {
            return nil
        }
        guard let send,
              send.denom == (payload.coin.isNativeToken ? payload.coin.chain.feeUnit : payload.coin.contractAddress),
              let value = Decimal(string: send.raw)
        else { return nil }
        return (send.recipient, value / pow(10, payload.coin.decimals))
    }

    /// The one `cosmos-sdk/MsgSend` of an amino body; nil for batches, other
    /// message types, multi-coin sends, or malformed JSON.
    private static func aminoSend(_ amino: SignAmino) -> (recipient: String, denom: String, raw: String)? {
        struct Send: Decodable {
            struct Coin: Decodable { let denom: String; let amount: String }
            let toAddress: String
            let amount: [Coin]
            enum CodingKeys: String, CodingKey { case toAddress = "to_address", amount }
        }
        guard amino.msgs.count == 1, amino.msgs[0].type == "cosmos-sdk/MsgSend",
              let send = try? JSONDecoder().decode(Send.self, from: Data(amino.msgs[0].value.utf8)),
              !send.toAddress.isEmpty, send.amount.count == 1,
              !send.amount[0].amount.isEmpty, send.amount[0].amount.allSatisfy({ ("0"..."9").contains($0) })
        else { return nil }
        return (send.toAddress, send.amount[0].denom, send.amount[0].amount)
    }

    private static func voteTitle(_ option: Int) -> String {
        DydxVoteOption.displayTitle(for: TW_Cosmos_Proto_Message.VoteOption(rawValue: option) ?? .unspecified)
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

private extension KeysignPayload {
    /// To and amount of these payloads come from the signed content, never `toAddress` / `toAmount`.
    var hasSignedCosmosBody: Bool { signDirect != nil || signAmino != nil }
}
