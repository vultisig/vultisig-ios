//
//  InstructionPrompt.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct InstructionPrompt: View {

    let networkType: NetworkPromptType

    var body: some View {
        content
    }

    var phoneContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.bgButtonPrimary)

            Text(networkType.getInstruction())
                .font(Theme.fonts.caption10)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 60)
    }

    var padContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.bgButtonPrimary)

            Text(networkType.getInstruction())
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 80)
    }
}

#Preview {
    ZStack {
        Background()
        InstructionPrompt(networkType: .Internet)
    }
}
