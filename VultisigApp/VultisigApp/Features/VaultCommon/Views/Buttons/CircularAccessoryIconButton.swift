//
//  CircularAccessoryIconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct CircularAccessoryIconButton: View {
    let icon: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.primaryAccent4, size: 16)
                .padding(12)
                .background(Circle().fill(Theme.colors.bgButtonSecondary))
        }
    }
}

#Preview {
    ScrollView {
        CircularAccessoryIconButton(icon: "settings") {}
        CircularAccessoryIconButton(icon: "x") {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
