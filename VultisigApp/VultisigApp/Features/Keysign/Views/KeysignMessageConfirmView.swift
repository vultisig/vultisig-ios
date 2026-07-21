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
                        hero: LimitOrderCancelPresentation.hero(forSignedMemo: viewModel.keysignPayload?.memo)
                            ?? viewModel.heroContent,
                        tokenDisplay: viewModel.decodedTokenDisplay,
                        tokenDisplayIsUnlimited: viewModel.decodedTokenIsUnlimited,
                        vault: viewModel.vault,
                        dappMetadata: viewModel.dappMetadata
                    ),
                    securityScannerState: $viewModel.securityScannerState
                )

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
