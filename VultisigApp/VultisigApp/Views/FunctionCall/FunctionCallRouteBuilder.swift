//
//  FunctionCallRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct FunctionCallRouteBuilder {
    
    @ViewBuilder
    func buildDetailsScreen(
        defaultCoin: Coin?,
        sendTx: SendTransaction,
        vault: Vault
    ) -> some View {
        FunctionCallDetailsScreen(
            vault: vault,
            tx: sendTx,
            defaultCoin: defaultCoin
        )
    }
    
    @ViewBuilder
    func buildVerifyScreen(tx: SendTransaction, vault: Vault) -> some View {
        FunctionCallVerifyScreen(tx: tx, vault: vault)
    }
    
    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        tx: SendTransaction,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        FunctionCallPairScreen(
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
    func buildFunctionTransactionScreen(
        vault: Vault,
        transactionType: FunctionTransactionType
    ) -> some View {
        FunctionTransactionScreen(vault: vault, transactionType: transactionType)
    }
}
