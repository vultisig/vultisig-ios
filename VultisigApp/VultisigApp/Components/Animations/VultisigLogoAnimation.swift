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
            Image("vultisig-logo")
                .resizable()
                .scaledToFit()
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
