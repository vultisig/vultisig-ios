//
//  QBTCClaimRouter.swift
//  VultisigApp
//

import SwiftUI

struct QBTCClaimRouter {
    private let viewBuilder = QBTCClaimRouteBuilder()

    @ViewBuilder
    func build(_ route: QBTCClaimRoute) -> some View {
        switch route {
        case .pair(let vault, let keysignPayload, let session, let qbtcCoin, let selectedUtxos):
            viewBuilder.buildPairScreen(
                vault: vault,
                keysignPayload: keysignPayload,
                session: session,
                qbtcCoin: qbtcCoin,
                selectedUtxos: selectedUtxos
            )
        case .keysign(let vault, let btcCoin, let qbtcCoin, let selectedUtxos, let fastVaultPassword, let session, let participants):
            viewBuilder.buildKeysignScreen(
                vault: vault,
                btcCoin: btcCoin,
                qbtcCoin: qbtcCoin,
                selectedUtxos: selectedUtxos,
                fastVaultPassword: fastVaultPassword,
                session: session,
                participants: participants
            )
        case .done(let result, let vault, let btcCoin, let qbtcCoin):
            viewBuilder.buildDoneScreen(
                result: result,
                vault: vault,
                btcCoin: btcCoin,
                qbtcCoin: qbtcCoin
            )
        }
    }
}
