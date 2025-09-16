//
//  TabBarAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/09/2025.
//

import SwiftUI

struct TabBarAccessoryButton: View {
    let icon: String
    var action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 99))
        } else {
            button
        }
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textLight, size: 24)
                .padding(20)
                .background(Circle().fill(Theme.colors.primaryAccent3))
        }
    }
}
