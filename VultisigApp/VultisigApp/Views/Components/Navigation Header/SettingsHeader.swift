//
//  SettingsHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-10.
//

import SwiftUI

struct SettingsHeader: View {

    var body: some View {
        HStack {
            text
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    var text: some View {
        Text(NSLocalizedString("settings", comment: "Settings"))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }
}

#Preview {
    SettingsHeader()
}
