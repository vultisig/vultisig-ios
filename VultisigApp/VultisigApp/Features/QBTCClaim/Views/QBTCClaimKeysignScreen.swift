//
//  QBTCClaimKeysignScreen.swift
//  VultisigApp
//
//  Renders the QBTC claim BTC ECDSA round + proof-service step via the
//  same `SendCryptoKeysignView` primitive used by `KeysignView` for
//  in-progress phases. Visual identity with Send is structural: both
//  flows render the same view. Background TSS logic is driven by
//  `QBTCClaimKeysignViewModel`.
//

import SwiftUI

struct QBTCClaimKeysignScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel: QBTCClaimKeysignViewModel
    let qbtcCoin: Coin

    init(
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo],
        fastVaultPassword: String?,
        session: KeysignSessionInfo?,
        participants: [String]
    ) {
        self.qbtcCoin = qbtcCoin
        _viewModel = StateObject(wrappedValue: QBTCClaimKeysignViewModel(
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            selectedUtxos: selectedUtxos,
            fastVaultPassword: fastVaultPassword,
            session: session,
            participants: participants
        ))
    }

    var body: some View {
        Screen {
            SendCryptoKeysignView(
                title: viewModel.errorTitle,
                showError: viewModel.isError,
                coinLogo: qbtcCoin.logo,
                errorButtonTitle: "tryAgain".localized,
                errorAction: { Task { await viewModel.retry() } }
            )
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
        .task { await viewModel.run() }
        .onChange(of: viewModel.runResult) { _, result in
            guard let result else { return }
            router.navigate(
                to: QBTCClaimRoute.done(
                    result: result,
                    vault: viewModel.vault,
                    btcCoin: viewModel.btcCoin,
                    qbtcCoin: qbtcCoin
                )
            )
        }
    }
}
