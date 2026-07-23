//
//  KeysignMessageConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                let fees = viewModel.getCalculatedNetworkFee()
                let lpDictionary = lpMemoDictionary(for: viewModel.keysignPayload)
                // XRP destination tag the joiner will actually sign (field-
                // preferred, else the canonical memo carrier). It owns a labeled
                // row; the numeric memo CARRIER is never shown as a memo. A
                // genuine text memo (tag+memo combo, or memo-only) still shows in
                // the memo row alongside the tag, so the joiner sees everything
                // it is about to sign.
                let ripplePayload = viewModel.keysignPayload
                let rippleDestinationTag = ripplePayload.flatMap { RippleDestinationTag.displayTag(for: $0) }
                let rippleMemo = ripplePayload.flatMap { RippleDestinationTag.displayMemo(for: $0) }
                // Only a PLAIN XRP payment routes its memo through the tag-aware
                // display: the numeric tag carrier is suppressed (shown as the
                // tag row) while a genuine text memo (combo / memo-only) shows.
                // XRP SWAPS keep the raw memo (their on-chain routing memo).
                let isRipplePlainPayment = ripplePayload?.coin.chain == .ripple && ripplePayload?.swapPayload == nil
                // A limit-order PLACEMENT, reconstructed from the `=<:` memo the
                // way the cancel path reads its `m=<:` one. When present it takes
                // precedence over the generic simulation hero, which would show a
                // co-signer a plain deposit/swap rather than the resting order it
                // is actually signing. `nil` for every non-placement memo.
                let placement = LimitOrderPlacementPresentation.display(for: viewModel.keysignPayload)
                SendCryptoVerifySummaryView(
                    input: SendCryptoVerifySummary(
                        fromName: viewModel.vault.name,
                        fromAddress: viewModel.keysignPayload?.coin.address ?? .empty,
                        toAddress: viewModel.keysignPayload?.toAddress ?? .empty,
                        network: viewModel.keysignPayload?.coin.chain.name ?? .empty,
                        networkImage: viewModel.keysignPayload?.coin.chain.logo ?? .empty,
                        memo: isRipplePlainPayment ? (rippleMemo ?? .empty) : (viewModel.memo ?? .empty),
                        destinationTag: rippleDestinationTag.map(String.init),
                        decodedFunctionSignature: viewModel.decodedFunctionSignature,
                        decodedFunctionArguments: viewModel.decodedFunctionArguments,
                        memoFunctionDictionary: lpDictionary,
                        feeCrypto: fees.feeCrypto,
                        feeFiat: fees.feeFiat,
                        coinImage: viewModel.keysignPayload?.coin.logo ?? .empty,
                        amount: lpAmountTitle(for: viewModel.keysignPayload, lpDictionary: lpDictionary),
                        // LP memos render a compound "<amt> <ticker> → <pool> LP"
                        // title, so their fiat would be misleading — suppress it.
                        amountFiat: lpDictionary == nil ? viewModel.getAmountFiat() : "",
                        coinTicker: viewModel.keysignPayload?.coin.ticker ?? .empty,
                        keysignPayload: viewModel.keysignPayload,
                        // A co-signer sees only the payload, so the `m=<` memo is
                        // what identifies a limit-order cancel — the same thing
                        // THORChain reads. It takes precedence over the
                        // simulation-derived hero: a cancel's dust transfer
                        // simulates as an ordinary send, which is exactly the
                        // reading this replaces.
                        hero: LimitOrderCancelPresentation.hero(
                            forSignedMemo: viewModel.keysignPayload?.memo
                        ) ?? LimitOrderPlacementPresentation.hero(
                            memo: viewModel.keysignPayload?.memo,
                            display: placement
                        ) ?? viewModel.heroContent,
                        tokenDisplay: viewModel.decodedTokenDisplay,
                        tokenDisplayIsUnlimited: viewModel.decodedTokenIsUnlimited,
                        vault: viewModel.vault,
                        dappMetadata: viewModel.dappMetadata,
                        // Target price + expiry for a placement — the initiator's
                        // limit Verify rows, as cost-style rows beneath the fee.
                        additionalRows: limitOrderSummaryRows(placement: placement)
                    ),
                    securityScannerState: $viewModel.securityScannerState
                ) {
                    limitOrderDisclosures
                }

                PrimaryButton(title: "joinTransactionSigning", isLoading: viewModel.isJoiningCommittee) {
                    viewModel.joinKeysignCommittee()
                }
                .disabled(viewModel.isJoiningCommittee)
            }
            .task {
                async let thor: Void = viewModel.loadThorchainID()
                async let fn: Void = viewModel.loadFunctionName()
                async let sim: Void = viewModel.loadSimulation()
                _ = await (thor, fn, sim)
            }
        }
        .navigationTitle("sendOverview")
    }

    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(Theme.fonts.bodyLMedium)
    }

    /// What a limit-order CANCEL says before it is signed — the initiator's
    /// "what cancelling does" explanation (`FunctionCallVerifyScreen`), verbatim
    /// static copy a co-signer can show from the payload alone: the order closes,
    /// anything already filled stays paid out, the unfilled remainder is refunded,
    /// for one network fee.
    ///
    /// ⚠️ The donated dust is NOT here. It moved UP into the summary card's cost
    /// rows (`limitOrderSummaryRows`, "Kept by THORChain"), matching the initiator
    /// — which deliberately stopped alarm-styling a routine, fully-disclosed
    /// charge. The initiator's other cancel disclosures (duplicate-order warning,
    /// balance objection, stale-order / insufficient-fee notices) are OMITTED
    /// here: each needs the vault's OTHER stored orders or a live balance /
    /// eligibility check that a co-signer, holding only this payload, cannot do.
    @ViewBuilder
    private var limitOrderDisclosures: some View {
        if LimitOrderCancelPresentation.isCancel(memo: viewModel.keysignPayload?.memo) {
            Text("limitSwap.cancel.explanation".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Cost-style rows shown beneath the network fee for a limit order, mirroring
    /// the initiator's Verify.
    ///
    /// - PLACEMENT: the target price (`1 <source> = <price> <target>`) and, when
    ///   the memo's interval is a whole number of hours, the expiry.
    /// - CANCEL: the dust an L1 cancel donates to the pool with no refund path,
    ///   framed as the cost it is ("Kept by THORChain") rather than a red alert —
    ///   the same reframing the initiator made in
    ///   `FunctionCallVerifyScreen.cancelLimitOrderRows`. Nothing on the THORChain
    ///   route, which attaches no dust.
    ///
    /// Empty for every other transaction, so no other path changes.
    private func limitOrderSummaryRows(
        placement: LimitOrderPlacementPresentation.Display?
    ) -> [SendCryptoVerifySummaryRow] {
        if let placement {
            var rows: [SendCryptoVerifySummaryRow] = []
            if let targetPrice = placement.targetPriceValue {
                rows.append(SendCryptoVerifySummaryRow(title: "limitSwap.detail.target", value: targetPrice))
            }
            if let expiry = placement.expiryValue {
                rows.append(SendCryptoVerifySummaryRow(title: "limitSwap.expiry", value: expiry))
            }
            return rows
        }
        if let dust = LimitOrderCancelPresentation.attachedDust(in: viewModel.keysignPayload) {
            return [SendCryptoVerifySummaryRow(
                title: "limitSwap.cancel.donatedDustRow",
                value: "\(dust.amount) \(dust.ticker)"
            )]
        }
        return []
    }

    /// Reconstructs the LP `memoFunctionDictionary` from a THORChain LP add/remove memo so the
    /// joiner verify screen mirrors the Pool / Paired Address / Memo rows shown to the initiator.
    /// Returns `nil` for non-LP memos so unrelated transactions are unaffected.
    private func lpMemoDictionary(for payload: KeysignPayload?) -> [String: String]? {
        guard let memo = payload?.memo, !memo.isEmpty else { return nil }
        let parts = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let prefix = parts.first else { return nil }

        switch prefix {
        case "+":
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            var dict: [String: String] = ["pool": parts[1]]
            if parts.count >= 3, !parts[2].isEmpty {
                dict["pairedAddress"] = parts[2]
            }
            dict["memo"] = memo
            return dict
        case "-":
            guard parts.count >= 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
            var dict: [String: String] = ["pool": parts[1]]
            if let basisPoints = Int(parts[2]) {
                let percentage = Double(basisPoints) / 100.0
                dict["withdrawPercentage"] = "\(percentage)%"
            }
            dict["memo"] = memo
            return dict
        default:
            return nil
        }
    }

    /// Mirrors `FunctionCallVerifyScreen.getAmount()` so the joiner shows the same
    /// `<amount> <ticker> → <pool> LP` title as the initiator for LP operations.
    private func lpAmountTitle(for payload: KeysignPayload?, lpDictionary: [String: String]?) -> String {
        let defaultAmount = payload?.toAmountString ?? .empty
        guard let payload, let pool = lpDictionary?["pool"], !pool.isEmpty else {
            return defaultAmount
        }
        let cleanPoolName = ThorchainService.cleanPoolName(pool)
        return defaultAmount + " " + payload.coin.ticker + " → " + cleanPoolName + " LP"
    }
}

#Preview {
    ZStack {
        Background()
        KeysignMessageConfirmView(viewModel: JoinKeysignViewModel())
    }
}
