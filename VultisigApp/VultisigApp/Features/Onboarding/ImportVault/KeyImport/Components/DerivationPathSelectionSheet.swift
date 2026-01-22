//
//  DerivationPathSelectionSheet.swift
//  VultisigApp
//

import SwiftUI

struct DerivationPathSelectionSheet: View {
    let chain: Chain
    @Binding var selectedPath: DerivationPath
    @Binding var isPresented: Bool
    let onSelect: (DerivationPath) -> Void

    private func selectPath(_ path: DerivationPath) {
        selectedPath = path
        onSelect(path)
        isPresented = false
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("whereDoYouMigrateFrom".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(.top, 12)

            VStack(spacing: 12) {
                DerivationOptionButton(
                    icon: "phantom",
                    title: "phantomWallet".localized,
                    action: { selectPath(.phantom) }
                )

                DerivationOptionButton(
                    icon: "wallet-4",
                    title: "standardSolanaWallet".localized,
                    action: { selectPath(.default) }
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
        .presentationDetents([.height(330)])
        .presentationBackground(Theme.colors.bgPrimary)
        .presentationDragIndicator(.visible)
    }
}

struct DerivationOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                Text(title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.colors.bgSurface1)
            )
        }
    }
}
