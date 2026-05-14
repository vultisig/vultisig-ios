//
//  QBTCClaimRunningView.swift
//  VultisigApp
//
//  Phase-aware progress UI. Driven directly by the orchestrator's
//  `phase` published state. The proof step warns the user about a
//  potentially long wait (~5 min) — service-side broadcast happens
//  in the same round-trip. Visually reuses `KeysignAnimationView`
//  (same Rive file as the standard keysign flow) so the QBTC claim
//  feels identical to a regular send.
//

import SwiftUI

struct QBTCClaimRunningView: View {
    let phase: QBTCClaimPhase
    /// QBTC coin logo string passed through to the keysign animation so
    /// the `toToken` slot renders the right asset.
    let coinLogo: String?

    @State private var connected: Bool = true

    init(phase: QBTCClaimPhase, coinLogo: String? = "qbtc") {
        self.phase = phase
        self.coinLogo = coinLogo
    }

    var body: some View {
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
                .padding(.horizontal, 24)
            Spacer()
        }
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
