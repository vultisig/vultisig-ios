//
//  AgentThinkingIndicator.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.colors.textTertiary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(16)

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    AgentThinkingIndicator()
        .padding()
        .background(Theme.colors.bgPrimary)
}
