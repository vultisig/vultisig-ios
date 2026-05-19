//
//  QBTCClaimPairScreen.swift
//  VultisigApp
//
//  SecureVault pairing screen for the QBTC claim flow. Wraps the
//  standard `KeysignDiscoveryView` with a preset session so the QR
//  shows the session the orchestrator will run on. When the peer joins
//  and `KeysignDiscoveryView` produces a `KeysignInput`, the screen
//  routes to `QBTCClaimRoute.keysign` to drive the BTC ECDSA round.
//

import SwiftUI

struct QBTCClaimPairScreen: View {
    @Environment(\.router) var router
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    let keysignPayload: KeysignPayload
    let session: KeysignSessionInfo
    let qbtcCoin: Coin
    let selectedUtxos: [ClaimableUtxo]

    var body: some View {
        Screen {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: nil,
                shareSheetViewModel: shareSheetViewModel,
                previewType: .Send,
                contentPadding: 0,
                presetSession: session
            ) { input in
                router.navigate(
                    to: QBTCClaimRoute.keysign(
                        vault: vault,
                        btcCoin: keysignPayload.coin,
                        qbtcCoin: qbtcCoin,
                        selectedUtxos: selectedUtxos,
                        fastVaultPassword: nil,
                        session: session,
                        participants: input.keysignCommittee
                    )
                )
            }
        }
        .screenTitle("pair".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
            }
        }
    }
}
