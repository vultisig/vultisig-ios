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
                    .frame(maxWidth: 64, maxHeight: 64)
                // The wordmark the animation ends on, so the static stand-in
                // reads as the same screen rather than a cropped version of it.
                //
                // Through a key even though every locale holds the same value:
                // the rule here is that no user-facing string is hardcoded, and
                // a product name is not worth the exception — a locale that ever
                // needs to transliterate it then has somewhere to do so.
                Text("vultisigBrandName".localized)
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
