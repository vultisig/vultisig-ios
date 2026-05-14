//
//  QBTCClaimJoinView.swift
//  VultisigApp
//
//  Peer-side view for the multi-round QBTC claim. Observes
//  `QBTCClaimJoinDriver.phase` and renders progress + verification +
//  result UI. Replaces the standard `keysignView` rendering on the
//  joiner side when the scanned QR carried a `qbtcClaimContext`.
//  Uses `KeysignAnimationView` during signing phases so the peer-side
//  visual matches a normal join keysign run.
//

import SwiftUI

struct QBTCClaimJoinView: View {
    @ObservedObject var driver: QBTCClaimJoinDriver
    var coinLogo: String?

    @State private var connected: Bool = true

    init(driver: QBTCClaimJoinDriver, coinLogo: String? = "qbtc") {
        self.driver = driver
        self.coinLogo = coinLogo
    }

    var body: some View {
        VStack(spacing: 24) {
            switch driver.phase {
            case .awaitingRound1Start:
                progressBlock(
                    title: "qbtcClaimJoinAwaitingStartTitle".localized,
                    detail: "qbtcClaimJoinAwaitingStartDetail".localized
                )
            case .signingRound1:
                progressBlock(
                    title: "qbtcClaimSigningBtcTitle".localized,
                    detail: "qbtcClaimSigningBtcDetail".localized
                )
            case .completed:
                resultBlock
            case .failed(let message):
                errorBlock(message)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressBlock(title: String, detail: String) -> some View {
        VStack(spacing: 24) {
            KeysignAnimationView(connected: $connected, coinLogo: coinLogo)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var resultBlock: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.colors.alertSuccess)
            Text("qbtcClaimJoinDoneTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("qbtcClaimJoinDoneDetail".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.colors.alertError)
            Text("qbtcClaimJoinFailedTitle".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(message)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
