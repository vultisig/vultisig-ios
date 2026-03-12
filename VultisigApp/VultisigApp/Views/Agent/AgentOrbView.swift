//
//  AgentOrbView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2026-03-12.
//

import SwiftUI

struct AgentOrbView: View {
    var size: CGFloat = 28
    var animated: Bool = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.colors.turquoise.opacity(0.4),
                            Theme.colors.primaryAccent3.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(pulsing ? 1.15 : 1.0)
                .opacity(pulsing ? 0.8 : 1.0)

            // Inner orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.colors.turquoise, Theme.colors.primaryAccent3],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        AgentOrbView(size: 80, animated: true)
        AgentOrbView(size: 40, animated: true)
        AgentOrbView(size: 24, animated: false)
    }
    .padding(40)
    .background(Theme.colors.bgPrimary)
}
