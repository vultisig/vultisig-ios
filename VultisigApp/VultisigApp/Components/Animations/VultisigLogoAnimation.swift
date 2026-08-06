//
//  VultisigLogoAnimation.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/02/2026.
//

import SwiftUI
import RiveRuntime

struct VultisigLogoAnimation: View {
    /// Render a static placeholder image instead of the live Rive animation.
    /// Set by snapshot tests so the captured frame is deterministic — Rive
    /// runs on its own clock and produces frame-by-frame drift otherwise.
    var isStatic: Bool = false

    @State var animationVM: RiveViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            content
            Spacer()
        }
        .onLoad(perform: onLoad)
    }

    @ViewBuilder
    private var content: some View {
        if isStatic {
            VStack(spacing: 12) {
                // Bounded rather than free-scaling. Left to `scaledToFit` alone
                // the mark took whatever width the container offered, which on
                // the privacy cover meant a logo the height of the screen.
                Image("vultisig-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 100, maxHeight: 100)
                // The wordmark the animation ends on, so the static stand-in
                // reads as the same screen rather than a cropped version of it.
                // Not localized: it is the product's name, matching
                // `QRShareSheetImage`.
                Text("Vultisig")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        } else {
            animationVM?.view()
        }
    }

    func onLoad() {
        guard !isStatic else { return }
        animationVM = RiveViewModel(fileName: "splash_logo", autoPlay: true)
        animationVM?.fit = .contain
    }
}

#Preview {
    Screen {
        VultisigLogoAnimation()
    }
}
