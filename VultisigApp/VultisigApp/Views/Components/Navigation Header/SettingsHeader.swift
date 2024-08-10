//
//  SettingsHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-10.
//

import SwiftUI

struct SettingsHeader: View {
    @Binding var showMenu: Bool
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackSheetButton(showSheet: $showMenu)
    }
    
    var text: some View {
        Text(NSLocalizedString("settings", comment: "Settings"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    SettingsHeader(showMenu: .constant(true))
}
