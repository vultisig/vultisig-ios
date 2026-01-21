//
//  Logo.swift
//  VultisigApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct VultisigLogo: View {
    var isAnimated: Bool = true

    @State var didAppear = false
    @State var showTexts = true

    var body: some View {
        container
            .onAppear {
                setData()
            }
    }

    var content: some View {
        VStack(spacing: 18) {
            primaryLogo
            if showTexts {
                title
            }
        }
    }

    var primaryLogo: some View {
        Image("VultisigLogoSquared")
            .resizable()
            .frame(width: 60, height: 60)
            .scaleEffect(didAppear ? 1 : 0)
            .opacity(didAppear ? 1 : 0)
    }

    var title: some View {
        Text("Vultisig")
            .font(Theme.fonts.title1)
            .foregroundColor(Theme.colors.textPrimary)
            .opacity(didAppear ? 1 : 0)
            .animation(
                isAnimated ? .easeIn(duration: 1) : .none,
                value: didAppear)
    }

    private func setData() {
        withAnimation(isAnimated ? .spring : .none) {
            didAppear = true
        }
    }
}

#Preview {
    ZStack {
        Background()
        VultisigLogo()
    }
}
