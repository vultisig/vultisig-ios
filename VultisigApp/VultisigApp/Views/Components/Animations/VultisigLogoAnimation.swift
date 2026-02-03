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
            Spacer()
        }
        .onLoad(perform: onLoad)
        .onDisappear(perform: onDisappear)
    }

    func onLoad() {
        animationVM = RiveViewModel(fileName: "splash_logo", autoPlay: true)
        animationVM?.fit = .contain
    }

    func onDisappear() {
        animationVM?.stop()
        animationVM = nil
    }
}

#Preview {
    Screen {
        VultisigLogoAnimation()
    }
}
