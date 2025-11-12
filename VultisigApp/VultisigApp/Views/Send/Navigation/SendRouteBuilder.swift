//
//  SendRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendRouteBuilder {
    
    @ViewBuilder
    func buildDetailsScreen(
        coin: Coin?,
        hasPreselectedCoin: Bool,
        tx: SendTransaction,
        vault: Vault
    ) -> some View {
        SendDetailsScreen(
            coin: coin,
            tx: tx,
            sendDetailsViewModel: SendDetailsViewModel(hasPreselectedCoin: hasPreselectedCoin),
            vault: vault
        )
    }
    
    @ViewBuilder
    func buildVerifyScreen(tx: SendTransaction, vault: Vault, keysignPayload: Binding<VerifyKeysignPayload?>) -> some View {
        SendVerifyScreen(tx: tx, vault: vault, keysignPayload: keysignPayload)
    }
    
    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        tx: SendTransaction,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        SendPairScreen(
            vault: vault,
            tx: tx,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword
        )
    }
    
    @ViewBuilder
    func buildKeysignScreen(input: KeysignInput, tx: SendTransaction) -> some View {
        SendKeysignScreen(input: input, tx: tx)
    }
    
    @ViewBuilder
    func buildDoneScreen(
        vault: Vault,
        hash: String,
        chain: Chain,
        tx: SendTransaction
    ) -> some View {
        SendDoneScreen(vault: vault, hash: hash, chain: chain, tx: tx)
    }
    
    @ViewBuilder
    func buildBuyScreen(address: String, blockChainCode: String, coinType: String) -> some View {
        BanxaDisclaimer(url:getBuyURL(address:address, blockChainCode: blockChainCode, coinType: coinType))
    }
    
    func getBuyURL(address: String, blockChainCode: String, coinType: String) -> URL {
        var components = URLComponents(string: "https://vultisig.banxa.com/")!
        components.queryItems = [
            URLQueryItem(name: "walletAddress", value: address),
            URLQueryItem(name: "blockchain", value: blockChainCode),
            URLQueryItem(name: "coinType", value: coinType),
        ]
        return components.url!
    }
    
}
