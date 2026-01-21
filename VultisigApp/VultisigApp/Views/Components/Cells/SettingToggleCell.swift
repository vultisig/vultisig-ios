//
//  SettingToggleCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

import SwiftUI

struct SettingToggleCell: View {
    
    let title: String
    let icon: String
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            iconBlock
            titleBlock
            Spacer()
            toggle
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .onTapGesture {
            isEnabled.toggle()
        }
    }
    
    var iconBlock: some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodyLRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var titleBlock: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var toggle: some View {
        Toggle("", isOn: $isEnabled)
            .labelsHidden()
            .scaleEffect(0.8)
            .frame(width: 48, height: 24)
    }
}

#Preview {
    SettingToggleCell(title: "language", icon: "globe", isEnabled: .constant(false))
        .environmentObject(SettingsViewModel())
}
