//
//  ImportVaultSelectionSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/12/2025.
//

import SwiftUI

struct ImportVaultSelectionSheet: View {
    @Binding var isPresented: Bool
    let onSeedphrase: () -> Void
    let onVaultShare: () -> Void

    var body: some View {
        Screen(showsBackButton: false, ignoresTopEdge: true) {
            VStack(spacing: 14) {
                Text("importVaultSelectionTitle")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .padding(.bottom, 6)

                importButton(
                    title: "importSeedphraseTitle".localized,
                    subtitle: "importSeedphraseSubtitle".localized,
                    icon: "import-seedphrase",
                    isNew: true,
                    action: onSeedphrase
                )

                importButton(
                    title: "importVaultShareTitle".localized,
                    subtitle: "importVaultShareSubtitle".localized,
                    caption: "importVaultShareCaption".localized,
                    icon: "import-vault-share",
                    isNew: false,
                    action: onVaultShare
                )
            }
        } toolbarItems: {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
        .applySheetSize(650, 400)
        .sheetStyle()
        .presentationDetents([.medium])
    }

    func importButton(
        title: String,
        subtitle: String,
        caption: String? = nil,
        icon: String,
        isNew: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                newTag.showIf(isNew)
                HStack(spacing: 8) {
                    Icon(named: icon, color: Theme.colors.alertInfo, size: 20)
                    Text(title)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.subtitle)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .font(Theme.fonts.footnote)
                    if let caption {
                        Text(caption)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .font(Theme.fonts.caption10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface1))
        }
        .buttonStyle(.plain)
    }

    private var newTag: some View {
        HStack(spacing: 4) {
            Icon(
                named: "stars",
                color: Theme.colors.alertWarning,
                size: 12
            )
            Text("new")
                .foregroundStyle(Theme.colors.alertWarning)
                .font(Theme.fonts.caption10)
        }
    }
}

#Preview {
    ImportVaultSelectionSheet(
        isPresented: .constant(false),
        onSeedphrase: {},
        onVaultShare: {}
    )
}
