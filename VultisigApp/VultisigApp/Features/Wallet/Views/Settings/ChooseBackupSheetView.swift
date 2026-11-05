//
//  ChooseBackupSheetView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import SwiftData
import SwiftUI

struct ChooseBackupSheetView: View, BottomSheetProperties {
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif
    @Query var vaults: [Vault]
    let vault: Vault

    var onDeviceBackup: () -> Void
    var onServerBackup: () -> Void

    var bgColor: Color? {
        Theme.colors.bgPrimary
    }

    var usesSystemGrabber: Bool { true }

    /// Puts the close button 16 below the sheet's top edge, above the container's grabber inset.
    private static let closeButtonTopOverlap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
            ToolbarButton(image: .xmark) {
                dismiss()
            }
            .padding(.top, -Self.closeButtonTopOverlap)
            .padding(.bottom, 11)
            #endif

            Text("chooseBackupMethod".localized)
                .settingsText(.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 14) {
                buttonView(
                    title: "deviceBackupTitle".localized,
                    subtitle: "deviceBackupDescription".localized,
                    icon: .laptopMobile,
                    action: onDeviceBackup
                )
                buttonView(
                    title: "serverBackupTitle".localized,
                    subtitle: "serverBackupDescription".localized,
                    icon: .cloudDownload,
                    action: onServerBackup
                )
            }
        }
    }

    func buttonView(title: String, subtitle: String, icon: ImageResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, color: Theme.colors.primaryAccent4, size: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .settingsText(.subtitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(subtitle)
                        .settingsText(.caption)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Icon(.chevronRight, color: Theme.colors.textSecondary, size: 16)
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.xl.shape)
            .overlay(Theme.radius.xl.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
