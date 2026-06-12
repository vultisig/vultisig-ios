//
//  SendRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendRouteBuilder {

    @MainActor
    @ViewBuilder
    func buildDetailsScreen(
        seed: SendDetailsSeed
    ) -> some View {
        SendDetailsScreen(
            coin: seed.hasPreselectedCoin ? seed.coin : nil,
            viewModel: makeDetailsViewModel(seed: seed),
            vault: seed.vault
        )
    }

    @ViewBuilder
    func buildVerifyScreen(
        tx: SendTransaction,
        retrySignal: SendRetrySignal,
        vault: Vault,
        prebuiltKeysignPayload: KeysignPayload? = nil
    ) -> some View {
        SendVerifyScreen(
            transaction: tx,
            retrySignal: retrySignal,
            vault: vault,
            prebuiltKeysignPayload: prebuiltKeysignPayload
        )
    }

    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        tx: SendTransaction,
        retrySignal: SendRetrySignal,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        SendPairScreen(
            vault: vault,
            tx: tx,
            retrySignal: retrySignal,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword
        )
    }

    @ViewBuilder
    func buildKeysignScreen(input: KeysignInput, tx: SendTransaction, retrySignal: SendRetrySignal) -> some View {
        SendKeysignScreen(input: input, tx: tx, retrySignal: retrySignal)
    }

    @ViewBuilder
    func buildDoneScreen(
        vault: Vault,
        hash: String,
        chain: Chain,
        tx: SendTransaction?,
        keysignPayload: KeysignPayload?
    ) -> some View {
        SendDoneScreen(vault: vault, hash: hash, chain: chain, tx: tx, keysignPayload: keysignPayload)
    }

    @ViewBuilder
    func buildTransactionDetailsScreen(input: TransactionDonePayload) -> some View {
        SendCryptoSecondaryDoneView(input: input)
    }

    @ViewBuilder
    func buildBuyScreen(address: String, blockChainCode: String, coinType: String) -> some View {
        BanxaDisclaimer(url: getBuyURL(address: address, blockChainCode: blockChainCode, coinType: coinType))
    }

    func getBuyURL(address: String, blockChainCode: String, coinType: String) -> URL {
        var components = URLComponents(string: "https://vultisig.banxa.com/")!
        components.queryItems = [
            URLQueryItem(name: "walletAddress", value: address),
            URLQueryItem(name: "blockchain", value: blockChainCode),
            URLQueryItem(name: "coinType", value: coinType)
        ]
        return components.url!
    }

    @MainActor
    private func makeDetailsViewModel(seed: SendDetailsSeed) -> SendDetailsViewModel {
        let viewModel = SendDetailsViewModel(
            coin: seed.coin,
            vault: seed.vault,
            hasPreselectedCoin: seed.hasPreselectedCoin
        )
        viewModel.hydrate(from: seed)
        return viewModel
    }

}
