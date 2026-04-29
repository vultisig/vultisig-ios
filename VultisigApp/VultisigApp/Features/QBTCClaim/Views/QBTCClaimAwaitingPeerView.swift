//
//  QBTCClaimAwaitingPeerView.swift
//  VultisigApp
//
//  SecureVault pairing screen — shows the QR the peer device scans
//  to join the multi-round claim, then surfaces observed peers as
//  they register on the relay session. Once the peer joins, the VM
//  transitions to `.claiming` and this view is replaced.
//

import SwiftUI

struct QBTCClaimAwaitingPeerView: View {
    @ObservedObject var viewModel: QBTCClaimViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("qbtcClaimPairTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("qbtcClaimPairDetail".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            qrBlock

            statusBlock

            Spacer()

            PrimaryButton(title: "qbtcClaimPairCancel".localized) {
                viewModel.resetForRetry()
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var qrBlock: some View {
        if let image = viewModel.pairingQrImage {
            image
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .padding(16)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(12)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: 280, maxHeight: 280)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if viewModel.observedPeers.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("qbtcClaimPairWaiting".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        } else {
            VStack(spacing: 4) {
                Text("qbtcClaimPairPeerJoined".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                ForEach(viewModel.observedPeers, id: \.self) { peer in
                    Text(peer)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
        }
    }
}
