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
        coin: Coin?,
        hasPreselectedCoin: Bool,
        tx: LegacySendTransaction,
        vault: Vault
    ) -> some View {
        SendDetailsScreen(
            coin: coin,
            viewModel: SendDetailsViewModel(
                coin: coin ?? tx.coin,
                vault: vault,
                hasPreselectedCoin: hasPreselectedCoin
            ),
            vault: vault
        )
    }

    @ViewBuilder
    func buildVerifyScreen(tx: SendTransaction, retrySignal: SendRetrySignal, vault: Vault) -> some View {
        SendVerifyScreen(transaction: tx, retrySignal: retrySignal, vault: vault)
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
    func buildCoinPickerScreen(coins: [Coin], tx: LegacySendTransaction) -> some View {
        CoinPickerView(coins: coins, tx: tx)
    }

    @ViewBuilder
    func buildTransactionDetailsScreen(input: SendCryptoContent) -> some View {
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

}
