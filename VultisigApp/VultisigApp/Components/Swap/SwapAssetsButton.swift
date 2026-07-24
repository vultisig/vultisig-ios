//
//  SwapAssetsButton.swift
//  VultisigApp
//
//  The circular "switch from/to" button shared by the market and limit swap
//  forms. Owns its own spring flip animation so both paths animate identically.
//

import SwiftUI

struct SwapAssetsButton: View {
    var isLoading: Bool = false
    let action: () -> Void

    @State private var rotated = false

    var body: some View {
        Button {
            rotated.toggle()
            action()
        } label: {
            ZStack {
                if isLoading {
                    CircularProgressIndicator(size: 20)
                } else {
                    Icon(.arrowsRotateCenter, color: Theme.colors.textPrimary, size: 18)
                }
            }
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.colors.bgButtonTertiary))
            .padding(2)
            .rotationEffect(.degrees(rotated ? 180 : 0))
            .animation(.spring, value: rotated)
        }
        // The 2pt gap between the tertiary disc and this stroke ring is
        // transparent — it reveals the real NotchedRectangle cavity behind the
        // button (was previously two page-colored `bgPrimary` circles faking a
        // hole, which only worked over a solid background).
        .overlay(Circle().stroke(Theme.colors.bgSurface2))
    }
}
