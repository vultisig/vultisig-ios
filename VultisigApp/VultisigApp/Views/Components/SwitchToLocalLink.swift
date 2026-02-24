//
//  SwitchToLocalLink.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-27.
//

import SwiftUI

struct SwitchToLocalLink: View {
    let isForKeygen: Bool
    @Binding var selectedNetwork: NetworkPromptType

    var body: some View {
        if selectedNetwork == .Internet {
            internetModeView
        } else {
            localModeView
        }
    }

    var internetModeView: some View {
        VStack(spacing: 8) {
            if isForKeygen {
                Text(NSLocalizedString("wantToCreateVaultPrivately", comment: ""))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            } else {
                Text(NSLocalizedString("wantToSignPrivately", comment: ""))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }

            Button {
                toggleNetwork()
            } label: {
                Text(NSLocalizedString("switchToLocalMode", comment: ""))
                    .underline()
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
    }

    var localModeView: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("switchBackToInternetMode", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            modeButton(
                title: NSLocalizedString("useStandardMode", comment: ""),
                background: Theme.colors.bgButtonTertiary,
                borderColor: .clear
            )
        }
    }

    private func modeButton(
        title: String,
        background: Color,
        borderColor: Color
    ) -> some View {
        Button {
            toggleNetwork()
        } label: {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
    }

    private func toggleNetwork() {
        withAnimation(.interpolatingSpring) {
            selectedNetwork = selectedNetwork == .Internet ? .Local : .Internet
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: .constant(.Internet))
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: .constant(.Local))
    }
}
