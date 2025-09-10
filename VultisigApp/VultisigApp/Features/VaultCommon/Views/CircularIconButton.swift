//
//  CircularIconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/09/2025.
//

import SwiftUI

struct CircularIconButton: View {
    let icon: String
    var action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .glassEffect(in: .rect(cornerRadius: 99))
        } else {
            button
        }
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textPrimary, size: 24)
                .padding(10)
        }
    }
}

#Preview {
    ScrollView {
        CircularIconButton(icon: "settings") {}
        CircularIconButton(icon: "x") {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
