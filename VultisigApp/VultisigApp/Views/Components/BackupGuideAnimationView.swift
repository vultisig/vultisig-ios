//
//  BackupGuideAnimationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-14.
//

import SwiftUI

enum BackupGuideAnimationType {
    case secure
    case keyImport
}

struct BackupGuideAnimationView: View {
    let vault: Vault?
    let type: BackupGuideAnimationType

    var body: some View {
        ScrollView(showsIndicators: false) {
            StepsAnimationView(
                title: "backupGuide".localized,
                steps: type == .secure ? 4 : 5
            ) { animationCell(index: $0)
            } header: {
                animationHeader
            }
            .padding(.top, isMacOS ? 0 : 32)
        }
    }

    @ViewBuilder
    func animationCell(index: Int) -> some View {
        switch type {
        case .secure:
            if let cell = secureAnimationCells[safe: index] {
                getCell(icon: cell.icon, text: cell.text)
            }
        case .keyImport:
            if let cell = keyImportAnimationCells[safe: index] {
                getCell(icon: cell.icon, text: cell.text)
            }
        }
    }

    var secureAnimationCells: [(icon: String, text: String)] {
        [
            (icon: "circle-info", text: String(format: "secureVaultSummaryText1".localized, vault?.signers.count ?? 0)),
            (icon: "cloud-check", text: "secureVaultSummaryText2"),
            (icon: "arrow-split", text: "secureVaultSummaryText3"),
            (icon: "cloud-check-2", text: "secureVaultSummaryText4")
        ]
    }

    var keyImportAnimationCells: [(icon: String, text: String)] {
        [
            (icon: "devices", text: "keyImportVaultSummaryText1"),
            (icon: "cloud-check", text: "secureVaultSummaryText2"),
            (icon: "arrow-split", text: "secureVaultSummaryText3"),
            (icon: "cloud-check-2", text: "secureVaultSummaryText4"),
            (icon: "unlocked", text: "keyImportVaultSummaryText5")
        ]
    }

    var animationHeader: some View {
        HStack {
            Icon(named: "shield", color: Theme.colors.alertSuccess, size: 16)
            Text(NSLocalizedString("secureVault", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 32,
                topTrailingRadius: 32
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 32,
                topTrailingRadius: 32
            )
            .inset(by: 1)
            .stroke(Theme.colors.borderLight, lineWidth: 2)
        )
        .offset(x: -1)
    }

    func getCell(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Icon(
                named: icon,
                color: Theme.colors.primaryAccent4,
                size: 24
            )

            Text(text.localized)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.fonts.bodySMedium)
    }
}

#Preview {
    Screen {
        BackupGuideAnimationView(vault: Vault.example, type: .keyImport)
    }
}
