//
//  TabBarAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/09/2025.
//

import SwiftUI

struct TabBarAccessoryButton: View {
    let icon: String
    let padding: CGFloat?
    let bgColor: Color?
    var action: () -> Void
    
    init(icon: String, padding: CGFloat? = nil, bgColor: Color? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.padding = padding
        self.bgColor = bgColor
        self.action = action
    }
    
    var body: some View {
        button
            .glassy(tint: bgColor ?? Theme.colors.primaryAccent3)
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textSecondary, size: 24)
                .padding(padding ?? 20)
                .background(Circle().fill(bgColor ?? Theme.colors.primaryAccent3))
        }
    }
}
