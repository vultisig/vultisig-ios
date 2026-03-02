//
//  DilithiumAlreadyGeneratedSheet.swift
//  VultisigApp
//

import SwiftUI

struct DilithiumAlreadyGeneratedSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            icon
            text
            button
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationBackground(Theme.colors.bgPrimary)
        .presentationDragIndicator(.visible)
    }

    var icon: some View {
        VaultSetupStepIcon(state: .active, icon: "atom-shield")
    }

    var text: some View {
        VStack(spacing: 12) {
            Text("dilithiumAlreadyGeneratedTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("dilithiumAlreadyGeneratedSubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    var button: some View {
        PrimaryButton(title: "ok".localized) {
            isPresented = false
        }
        .frame(maxWidth: 165)
    }
}
