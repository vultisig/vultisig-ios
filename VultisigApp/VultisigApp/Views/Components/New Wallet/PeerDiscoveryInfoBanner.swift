//
//  PeerDiscoveryInfoBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-28.
//

import SwiftUI
import RiveRuntime

struct PeerDiscoveryInfoBanner: View {
    @Binding var isPresented: Bool

    @State var animationVM: RiveViewModel? = nil

    var body: some View {
        ZStack {
            Background()
            content
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "peer_discovery_info_banner", autoPlay: true)
        }
        .onDisappear {
            animationVM?.stop()
        }
    }

    var content: some View {
        VStack(spacing: 36) {
            display
            text
            button
        }
    }

    var display: some View {
        ZStack {
            image
            animation
        }
        .edgesIgnoringSafeArea(.top)
    }

    var image: some View {
        Image("PeerDiscoveryInfoBanner")
            .resizable()
            .frame(width: 290, height: 230)
    }

    var animation: some View {
        animationVM?.view()
            .frame(width: 80, height: 80)
            .offset(x: -80, y: 6)
    }

    var text: some View {
        VStack(spacing: 12) {
            title
            description
        }
    }

    var title: some View {
        Group {
            Text(NSLocalizedString("peerDiscoveryInfoTitle1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary) +
            Text(NSLocalizedString("peerDiscoveryInfoTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(Theme.fonts.title2)
    }

    var description: some View {
        Text(NSLocalizedString("peerDiscoveryInfoDescription", comment: ""))
            .multilineTextAlignment(.center)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
            .padding(.horizontal, 32)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var button: some View {
        PrimaryButton(title: "gotIt") {
            isPresented = false
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
        .buttonStyle(.plain)
    }
}

#Preview {
    PeerDiscoveryInfoBanner(isPresented: .constant(false))
}
