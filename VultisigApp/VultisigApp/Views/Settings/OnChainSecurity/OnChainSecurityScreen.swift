//
//  OnChainSecurityScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct OnChainSecurityScreen: View {
    let title = "vaultSettingsSecurityTitle".localized
    let service = SecurityScannerSettingsService()

    @State var securityScannerEnabled: Bool = false
    @State var showSecurityScannerSheet: Bool = false

    var body: some View {
        Screen(title: title) {
            ScrollView {
                securityScannerCell
            }
            .frame(maxWidth: .infinity)
        }
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
        VStack(alignment: .leading, spacing: 2) {
            Text("vaultSettingsSecurityScreenTitleSwitch".localized)
                .font(Theme.fonts.bodyMMedium)
            Text("vaultSettingsSecurityScreenTitleContent".localized)
                .font(Theme.fonts.caption12)
            VultiToggle(isOn: $securityScannerEnabled)
        }
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
