//
//  VaultBannerCarouselIndicator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/10/2025.
//

import SwiftUI

struct VaultBannerCarouselIndicator: View {
    let indicatorIndex: Int
    @Binding var currentIndex: Int
    let bannersCount: Int

    @State var isActive: Bool = false
    @State var progress: CGFloat = 0

    let capsuleWidth: CGFloat = 20
    let capsuleHeight: CGFloat = BannerLayoutProperties.indicatorsHeight
    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)

    var body: some View {
        Capsule()
            .fill(Theme.colors.bgSurface2)
            .frame(width: isActive ? capsuleWidth : capsuleHeight, height: capsuleHeight)
            .padding(.horizontal, 0.1)
            .overlay(isActive ? overlayView : nil, alignment: .leading)
            .onLoad {
                updateIsActive()
            }
            .onChange(of: currentIndex) {
                updateIsActive()
            }
    }

    var overlayView: some View {
        Capsule()
            .fill(Theme.colors.textSecondary)
            .frame(width: progress, height: capsuleHeight + 0.1)
            .offset(x: -1)
            .onAppear {
                withAnimation(.linear(duration: 2.5).delay(0.5)) {
                    progress = capsuleWidth + 1
                }
            }
    }

    func updateIsActive() {
        withAnimation(animation) {
            isActive = currentIndex == indicatorIndex
            if !isActive {
                progress = 0
            }
        }
    }
}
