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
                SendCryptoVerifySummaryView(
                    input: SendCryptoVerifySummary(
                        fromName: viewModel.vault.name,
                        fromAddress: viewModel.keysignPayload?.coin.address ?? .empty,
                        toAddress: viewModel.keysignPayload?.toAddress ?? .empty,
                        network: viewModel.keysignPayload?.coin.chain.name ?? .empty,
                        networkImage: viewModel.keysignPayload?.coin.chain.logo ?? .empty,
                        memo: viewModel.memo ?? .empty,
                        decodedFunctionSignature: viewModel.decodedFunctionSignature,
                        decodedFunctionArguments: viewModel.decodedFunctionArguments,
                        memoFunctionDictionary: lpDictionary,
                        feeCrypto: fees.feeCrypto,
                        feeFiat: fees.feeFiat,
                        coinImage: viewModel.keysignPayload?.coin.logo ?? .empty,
                        amount: lpAmountTitle(for: viewModel.keysignPayload, lpDictionary: lpDictionary),
                        coinTicker: viewModel.keysignPayload?.coin.ticker ?? .empty,
                        keysignPayload: viewModel.keysignPayload,
                        hero: viewModel.heroContent,
                        tokenDisplay: viewModel.decodedTokenDisplay,
                        tokenDisplayIsUnlimited: viewModel.decodedTokenIsUnlimited,
                        vault: viewModel.vault,
                        dappMetadata: viewModel.dappMetadata
                    ),
                    securityScannerState: $viewModel.securityScannerState
                )

                PrimaryButton(title: "joinTransactionSigning") {
                    viewModel.joinKeysignCommittee()
                }
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
