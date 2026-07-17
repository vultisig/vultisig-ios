//
//  HelpButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

import SwiftUI

struct HelpButton: View {
    @Binding var isPresented: Bool
    var size: CGFloat = 44
    var iconSize: CGFloat = 22

    var body: some View {
        Button {
            withAnimation(.interpolatingSpring) { isPresented.toggle() }
        } label: {
            Icon(.circleInfo, color: Theme.colors.textPrimary, size: iconSize)
                .frame(width: size, height: size)
                .background(glassCircleBackground)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var glassCircleBackground: some View {
        Circle()
            .fill(Color.white.opacity(0.05))
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.05),
                                Color.clear,
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .glassy(shape: Circle())
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Theme.colors.bgPrimary.ignoresSafeArea()
        HelpButton(isPresented: .constant(false))
            .padding(.trailing, 16)
            .padding(.top, 60)
    }
}
