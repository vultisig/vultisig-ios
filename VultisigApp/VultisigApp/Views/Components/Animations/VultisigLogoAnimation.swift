//
//  VultisigLogoAnimation.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/02/2026.
//

import SwiftUI
import RiveRuntime

struct VultisigLogoAnimation: View {
    @State var animationVM: RiveViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            animationVM?.view()
                .onAppear(perform: playAnimation)
            Spacer()
        }
        .onLoad(perform: onLoad)
        .onDisappear(perform: onDisappear)
    }

    func onLoad() {
        animationVM = RiveViewModel(fileName: "splash_logo", autoPlay: false)
        animationVM?.fit = .contain
    }

    func onDisappear() {
        animationVM?.stop()
        animationVM = nil
    }

    func playAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            animationVM?.play(loop: .oneShot)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            animationVM?.pause()
        }
    }
}

#Preview {
    Screen {
        VultisigLogoAnimation()
    }
}
