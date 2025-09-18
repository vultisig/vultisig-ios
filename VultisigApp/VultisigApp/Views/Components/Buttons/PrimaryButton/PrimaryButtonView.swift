//
//  PrimaryButtonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButtonView: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?
    let isLoading: Bool
    
    init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        isLoading: Bool = false
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.isLoading = isLoading
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15)
            }
            
            Text(NSLocalizedString(title, comment: "Button Text"))
                .fixedSize(horizontal: true, vertical: false)
            
            if let trailingIcon {
                Icon(named: trailingIcon, color: Theme.colors.textPrimary, size: 15)
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PrimaryButtonView(title: "Next")
}
