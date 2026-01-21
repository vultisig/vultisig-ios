//
//  KeysignDiscoveryDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-11.
//

import SwiftUI

struct KeysignDiscoveryDisclaimer: View {
    let vault: Vault
    @Binding var showAlert: Bool

    var body: some View {
        HStack(spacing: 12) {
            infoIcon
            text
            closeButton
        }
        .foregroundColor(Theme.colors.textPrimary)
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    var infoIcon: some View {
        Image(systemName: "info.circle")
            .resizable()
            .frame(width: 16, height: 16)
    }

    var text: some View {
        let value = NSLocalizedString("keysignDiscoveryDisclaimer", comment: "") +
        String(describing: vault.getThreshold()) +
        NSLocalizedString("keysignDiscoveryDisclaimerDevice", comment: "")

        return Text(value)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var closeButton: some View {
        Button {
            showAlert = false
        } label: {
            closeButtonLabel
        }
    }

    var closeButtonLabel: some View {
        Image(systemName: "xmark")
            .resizable()
            .frame(width: 8, height: 8)
            .padding(8)
            .background(Theme.colors.border)
            .cornerRadius(16)
    }
}

#Preview {
    KeysignDiscoveryDisclaimer(vault: Vault.example, showAlert: .constant(false))
}
