//
//  AgentThinkingIndicator.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentThinkingIndicator: View {
    var currentStep: String?
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .symbolEffect(.pulse, isActive: animating)

                if let step = currentStep {
                    Text(step.uppercased())
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    ellipsisAnimation
                } else {
                    dotsAnimation
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }

    private var dotsAnimation: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.colors.textTertiary)
                    .frame(width: 6, height: 6)
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
    }

    private var ellipsisAnimation: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Text(".")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AgentThinkingIndicator()
        AgentThinkingIndicator(currentStep: "Analyzing route")
        AgentThinkingIndicator(currentStep: "Building transaction")
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
