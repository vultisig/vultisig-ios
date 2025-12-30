//
//  IconCapsule.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-04.
//

import SwiftUI

struct IconCapsule: View {
    let title: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                iconContent(icon)
            }
            
            titleContent
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgPrimary)
        .cornerRadius(50)
        .overlay(
            RoundedRectangle(cornerRadius: 50)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    var titleContent: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textSecondary)
            .font(Theme.fonts.caption12)
    }
    
    func iconContent(_ icon: String) -> some View {
        Image(systemName: icon)
            .foregroundColor(Theme.colors.bgButtonPrimary)
            .font(Theme.fonts.bodyMMedium)
    }
}

#Preview {
    IconCapsule(title: "secureVault", icon: "shield")
}
