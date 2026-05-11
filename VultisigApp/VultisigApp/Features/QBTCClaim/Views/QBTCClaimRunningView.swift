//
//  QBTCClaimRunningView.swift
//  VultisigApp
//
//  Phase-aware progress UI. Driven directly by the orchestrator's
//  `phase` published state. The proof step warns the user about a
//  potentially long wait (~5 min) — service-side broadcast happens
//  in the same round-trip.
//

import SwiftUI

struct QBTCClaimRunningView: View {
    let phase: QBTCClaimPhase

    var body: some View {
        VStack(spacing: 24) {
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
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch phase {
        case .idle, .signingBTC:
            return "qbtcClaimSigningBtcTitle".localized
        case .generatingProofAndBroadcasting:
            return "qbtcClaimGeneratingProofTitle".localized
        case .done, .failed:
            // The screen normally transitions out of .claiming before
            // we render these — fall back gracefully.
            return ""
        }
    }

    private var detail: String {
        switch phase {
        case .idle, .signingBTC:
            return "qbtcClaimSigningBtcDetail".localized
        case .generatingProofAndBroadcasting:
            return "qbtcClaimGeneratingProofDetail".localized
        case .done, .failed:
            return ""
        }
    }
}
