//
//  QBTCClaimJoinView.swift
//  VultisigApp
//
//  Peer-side view for the multi-round QBTC claim. Observes
//  `QBTCClaimJoinDriver.phase` and renders progress + verification +
//  result UI. Replaces the standard `keysignView` rendering on the
//  joiner side when the scanned QR carried a `qbtcClaimContext`.
//

import SwiftUI

struct QBTCClaimJoinView: View {
    @ObservedObject var driver: QBTCClaimJoinDriver

    var body: some View {
        VStack(spacing: 24) {
            switch driver.phase {
            case .awaitingRound1Start, .awaitingRound2Start:
                progressBlock(
                    title: "qbtcClaimJoinAwaitingStartTitle".localized,
                    detail: "qbtcClaimJoinAwaitingStartDetail".localized
                )
            case .signingRound1:
                progressBlock(
                    title: "qbtcClaimSigningBtcTitle".localized,
                    detail: "qbtcClaimSigningBtcDetail".localized
                )
            case .awaitingRound2Prep:
                progressBlock(
                    title: "qbtcClaimJoinWaitingPrepTitle".localized,
                    detail: "qbtcClaimGeneratingProofDetail".localized
                )
            case .verifyingRound2Prep:
                progressBlock(
                    title: "qbtcClaimJoinVerifyingTitle".localized,
                    detail: "qbtcClaimJoinVerifyingDetail".localized
                )
            case .signingRound2:
                progressBlock(
                    title: "qbtcClaimSigningMldsaTitle".localized,
                    detail: "qbtcClaimSigningMldsaDetail".localized
                )
            case .completed:
                resultBlock
            case .failed(let message):
                errorBlock(message)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressBlock(title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
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
