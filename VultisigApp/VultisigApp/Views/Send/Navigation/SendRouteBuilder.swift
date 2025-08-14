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
    func buildVerifyScreen(tx: SendTransaction, vault: Vault) -> some View {
        SendVerifyScreen(tx: tx, vault: vault)
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
}
