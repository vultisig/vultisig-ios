//
//  QBTCClaimJoinView.swift
//  VultisigApp
//
//  Peer-side view for the QBTC claim. Observes `QBTCClaimJoinDriver.phase`:
//  during signing it renders the same `SendCryptoKeysignView` primitive
//  the initiator uses (full-screen animation, no status text); on
//  completion it shows the same `QBTCClaimDoneScreen` the initiator
//  ends up on, populated from the relay-pushed tx hash + total sats.
//

import SwiftUI

struct QBTCClaimJoinView: View {
    @ObservedObject var driver: QBTCClaimJoinDriver
    var coinLogo: String?

    init(driver: QBTCClaimJoinDriver, coinLogo: String? = "qbtc") {
        self.driver = driver
        self.coinLogo = coinLogo
    }

    var body: some View {
        switch driver.phase {
        case .awaitingRound1Start, .signingRound1:
            SendCryptoKeysignView(coinLogo: coinLogo)
        case .completed(let result):
            doneScreen(result: result)
        case .failed(let message):
            SendCryptoKeysignView(
                title: message,
                showError: true,
                coinLogo: coinLogo
            )
        }
    }

    @ViewBuilder
    private func doneScreen(result: QBTCClaimRunResult?) -> some View {
        // The peer has the vault from the driver; BTC + QBTC coins are
        // derived from it. If the tx-hash push didn't arrive in time
        // (`result == nil`), surface the same animation the standard
        // peer keysign flow shows on completion.
        if let result,
           let btcCoin = driver.vault.nativeCoin(for: .bitcoin),
           let qbtcCoin = driver.vault.nativeCoin(for: .qbtc) {
            QBTCClaimDoneScreen(
                result: result,
                vault: driver.vault,
                btcCoin: btcCoin,
                qbtcCoin: qbtcCoin
            )
        } else {
            SendCryptoKeysignView(coinLogo: coinLogo)
        }
    }
}
