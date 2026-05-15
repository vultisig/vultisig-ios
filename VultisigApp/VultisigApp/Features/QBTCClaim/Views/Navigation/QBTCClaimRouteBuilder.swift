//
//  QBTCClaimRouteBuilder.swift
//  VultisigApp
//

import SwiftUI

struct QBTCClaimRouteBuilder {

    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        keysignPayload: KeysignPayload,
        session: KeysignSessionInfo,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo]
    ) -> some View {
        QBTCClaimPairScreen(
            vault: vault,
            keysignPayload: keysignPayload,
            session: session,
            qbtcCoin: qbtcCoin,
            selectedUtxos: selectedUtxos
        )
    }

    @ViewBuilder
    func buildKeysignScreen(
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo],
        fastVaultPassword: String?,
        session: KeysignSessionInfo?,
        participants: [String]
    ) -> some View {
        QBTCClaimKeysignScreen(
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            selectedUtxos: selectedUtxos,
            fastVaultPassword: fastVaultPassword,
            session: session,
            participants: participants
        )
    }

    @ViewBuilder
    func buildDoneScreen(
        result: QBTCClaimRunResult,
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin
    ) -> some View {
        QBTCClaimDoneScreen(
            result: result,
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin
        )
    }
}
