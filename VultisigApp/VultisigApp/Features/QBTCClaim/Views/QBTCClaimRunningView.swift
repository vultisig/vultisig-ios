//
//  QBTCClaimRunningView.swift
//  VultisigApp
//
//  Phase-aware progress UI. Driven directly by the orchestrator's
//  `phase` published state. The proof step warns the user about a
//  potentially long wait (~5 min).
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
        case .generatingProof:
            return "qbtcClaimGeneratingProofTitle".localized
        case .signingMLDSA:
            return "qbtcClaimSigningMldsaTitle".localized
        case .broadcasting:
            return "qbtcClaimBroadcastingTitle".localized
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
        case .generatingProof:
            return "qbtcClaimGeneratingProofDetail".localized
        case .signingMLDSA:
            return "qbtcClaimSigningMldsaDetail".localized
        case .broadcasting:
            return "qbtcClaimBroadcastingDetail".localized
        case .done, .failed:
            return ""
        }
    }
}
