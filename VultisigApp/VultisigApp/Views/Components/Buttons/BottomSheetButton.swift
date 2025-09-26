//
//  BottomSheetButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct BottomSheetButton: View {
    let icon: String
    let type: ButtonType
    var action: () -> Void
    
    init(icon: String, type: ButtonType = .primary, action: @escaping () -> Void) {
        self.icon = icon
        self.type = type
        self.action = action
    }
    
    var backgroundColor: Color {
        switch type {
        case .primary:
            Theme.colors.primaryAccent4
        case .secondary:
            Theme.colors.bgSecondary
        case .alert:
            Theme.colors.alertError
        }
    }
    
    var is26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .glassEffect(.regular.tint(backgroundColor).interactive())
        } else {
            button
        }
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textPrimary, size: 20)
                .padding(12)
                .background(is26 ? nil : Circle().fill(backgroundColor))
                .overlay(Circle().inset(by: 0.5).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
    }
}
