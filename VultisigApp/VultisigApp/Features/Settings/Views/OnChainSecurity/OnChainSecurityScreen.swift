//
//  OnChainSecurityScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct OnChainSecurityScreen: View {
    let title = "onChainSecurityScreenTitle".localized
    let service = SecurityScannerSettingsService()

    @State var securityScannerEnabled: Bool = false
    @State var showSecurityScannerSheet: Bool = false

    private static let topContentInset: CGFloat = 9

    var body: some View {
        Screen {
            ScrollView {
                securityScannerCell
            }
            .frame(maxWidth: .infinity)
        }
        .screenTitle(title)
        .onLoad {
            securityScannerEnabled = service.isEnabled
        }
        .bottomSheet(isPresented: $showSecurityScannerSheet) {
            SettingsSecurityScannerBottomSheet {
                toggleSecurityScanner(true)
            } onContinueAnyway: {
                toggleSecurityScanner(false)
            }
        }
        .onChange(of: securityScannerEnabled) { _, _ in
            onSecurityScannerToggle()
        }
    }

    var securityScannerCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("vaultSettingsSecurityScreenTitleSwitch".localized)
                .settingsText(.bodyM)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("vaultSettingsSecurityScreenTitleContent".localized)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textSecondary)
            HStack(spacing: 8) {
                Toggle("vaultSettingsSecurityScreenTitleSwitch".localized, isOn: $securityScannerEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsToggleStyle(size: .regular))
                Text((securityScannerEnabled ? "settingsToggleOn" : "settingsToggleOff").localized)
                    .settingsText(.bodyMRegular)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        }
        .padding(.top, Self.topContentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    func onSecurityScannerToggle() {
        guard !securityScannerEnabled else {
            toggleSecurityScanner(true)
            return
        }

        showSecurityScannerSheet = true
    }

    func toggleSecurityScanner(_ enabled: Bool) {
        securityScannerEnabled = enabled
        service.saveSecurityScannerStatus(enable: enabled)
        showSecurityScannerSheet = false
    }
}

#Preview {
    OnChainSecurityScreen()
}
