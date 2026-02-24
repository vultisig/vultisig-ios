//
//  SetupVaultSecureText.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-27.
//

import SwiftUI

struct SetupVaultSecureText: View {
    let selectedTab: SetupVaultState

    var body: some View {
        VStack(spacing: 0) {
            header
            dashedLine
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .cornerRadius(16)
        .padding(.vertical, 16)
    }

    var header: some View {
        ZStack {
            if selectedTab == .fast {
                headerText
                    .foregroundStyle(LinearGradient.primaryGradient)
            } else {
                headerText
                    .foregroundColor(Theme.colors.alertInfo)
            }
        }
    }

    var headerText: some View {
        Text(selectedTab.secureTextTitle)
            .font(Theme.fonts.bodyLMedium)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }

    var dashedLine: some View {
        Rectangle()
           .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
           .frame(height: 2)
           .frame(maxWidth: .infinity)
           .foregroundColor(Theme.colors.bgSurface2)
           .offset(y: 1)
    }

    var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3) { _ in
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.colors.bgButtonPrimary)
                        .frame(width: 16, height: 16)
                }
            }

            Text(selectedTab.secureTextDecription)
                .foregroundColor(Theme.colors.textPrimary)
                .lineSpacing(12)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .font(Theme.fonts.bodySMedium)
        .padding(24)
        .background(Theme.colors.bgSurface1)
    }
}

#Preview {
    SetupVaultSecureText(selectedTab: .secure)
}
