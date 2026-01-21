//
//  ChooseBackupSheetView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import SwiftData
import SwiftUI

struct ChooseBackupSheetView: View, BottomSheetProperties {
    @Query var vaults: [Vault]
    let vault: Vault

    var onDeviceBackup: () -> Void
    var onServerBackup: () -> Void

    var bgColor: Color? {
        Theme.colors.bgPrimary
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("chooseBackupMethod".localized)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)

            GradientListSeparator()

            VStack(spacing: 14) {
                buttonView(
                    title: "deviceBackupTitle".localized,
                    subtitle: "deviceBackupDescription".localized,
                    icon: "tablet-smartphone",
                    action: onDeviceBackup
                )
                buttonView(
                    title: "serverBackupTitle".localized,
                    subtitle: "serverBackupDescription".localized,
                    icon: "cloud",
                    action: onServerBackup
                )
            }
        }
    }

    func buttonView(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(named: icon)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                Spacer()
                Icon(named: "chevron-right", color: Theme.colors.textSecondary, size: 16)
            }
            .containerStyle(padding: 16)
        }
        .buttonStyle(.plain)
    }
}
