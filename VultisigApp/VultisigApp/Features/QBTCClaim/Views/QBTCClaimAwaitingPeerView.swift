//
//  QBTCClaimAwaitingPeerView.swift
//  VultisigApp
//
//  SecureVault pairing screen — shows the QR the peer device scans
//  to join the multi-round claim, then surfaces observed peers as
//  they register on the relay session. Once the peer joins, the VM
//  transitions to `.claiming` and this view is replaced.
//
//  Visually mirrors `PeerDiscoveryScreen` (Features/Keygen) so the
//  QBTC claim pairing feels identical to the standard secure-vault
//  pairing flow: rounded QR card with the gradient border, dots-
//  indicator status text, and a device list underneath.
//

import RiveRuntime
import SwiftUI

struct QBTCClaimAwaitingPeerView: View {
    @ObservedObject var viewModel: QBTCClaimViewModel

    @State private var dotsIndicatorVM: RiveViewModel?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                VStack(spacing: 32) {
                    pairingBarcode
                    statusText
                }
                .padding(.bottom, 8)
                deviceList
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: "qbtcClaimPairCancel".localized,
                type: .secondary
            ) {
                viewModel.resetForRetry()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var pairingBarcode: some View {
        Group {
            if let image = viewModel.pairingQrImage {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 280, maxHeight: 280)
        .padding(20)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(33)
        .overlay(
            RoundedRectangle(cornerRadius: 33)
                .stroke(Theme.colors.borderLight, lineWidth: 8)
        )
    }

    private var statusText: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                Text(statusMessage)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                dotsIndicatorVM?.view()
                    .frame(width: 12, height: 12)
                    .offset(y: 2)
            }
            .onAppear {
                if dotsIndicatorVM == nil {
                    dotsIndicatorVM = RiveViewModel(fileName: "dots_indicator", autoPlay: true)
                }
            }
            .onDisappear { dotsIndicatorVM?.stop() }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }

    private var statusMessage: String {
        viewModel.observedPeers.isEmpty
            ? "qbtcClaimPairWaiting".localized
            : "qbtcClaimPairPeerJoined".localized
    }

    private var deviceList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.observedPeers, id: \.self) { peer in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.colors.primaryAccent4)
                    Text(peer)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.colors.alertSuccess)
                }
                .padding(16)
                .background(Theme.colors.bgSurface1)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
