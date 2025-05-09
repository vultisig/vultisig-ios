//
//  SettingsAdvancedView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingsAdvancedView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            Background()
            container
        }
    }
    
    var content: some View {
        VStack {
            SettingToggleCell(
                title: "enableDKLS",
                icon: "timelapse",
                isEnabled: $settingsViewModel.isDKLSEnabled
            )
            
            SettingToggleCell(
                title: "Swap",
                icon: "timelapse",
                isEnabled: $settingsViewModel.allowSwap
            )
            
            SettingToggleCell(
                title: "MoonPay",
                icon: "timelapse",
                isEnabled: $settingsViewModel.moonpayEnabled
            )
        }
    }
}

#Preview {
    ZStack {
        Background()
        SettingsAdvancedView()
    }
    .environmentObject(SettingsViewModel())
}
