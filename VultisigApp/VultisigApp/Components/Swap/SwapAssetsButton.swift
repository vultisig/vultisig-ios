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
                    Icon(named: "arrow-bottom-top", color: Theme.colors.textPrimary, size: 18)
                }
            }
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.colors.bgButtonTertiary))
            .padding(2)
            .background(Circle().fill(Theme.colors.bgPrimary))
            .rotationEffect(.degrees(rotated ? 180 : 0))
            .animation(.spring, value: rotated)
        }
        .background(Circle().fill(Theme.colors.bgPrimary))
        .overlay(Circle().stroke(Theme.colors.bgSurface2))
    }
}
