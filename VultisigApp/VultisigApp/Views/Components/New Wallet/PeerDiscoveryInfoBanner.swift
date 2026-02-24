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
        .presentationDetents([.height(416)])
        .onAppear {
            animationVM = RiveViewModel(fileName: "PeerDiscoveryInfoBanner", autoPlay: true)
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
        .frame(maxWidth: 370)
    }

    var display: some View {
        ZStack {
            image
            animation
        }
        .edgesIgnoringSafeArea(.top)
    }

    var image: some View {
        Image("secure-qr-tutorial")
            .resizable()
            .frame(width: 290, height: 230)
    }

    var animation: some View {
        animationVM?.view()
            .frame(width: 80, height: 80)
            .offset(x: -16, y: -30)
    }

    var text: some View {
        VStack(spacing: 12) {
            title
            description
        }
    }

    var title: some View {
        Text(NSLocalizedString("peerDiscoveryInfoTitle", comment: ""))
            .font(Theme.fonts.title3)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }

    var description: some View {
        Text(NSLocalizedString("peerDiscoveryInfoDescription", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    var button: some View {
        PrimaryButton(title: "startScanning") {
            isPresented = false
        }
        .frame(maxWidth: 165)
    }
}

#Preview {
    Screen {
        VStack {}
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        PeerDiscoveryInfoBanner(isPresented: .constant(false))
    }
}
