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
                Image(systemName: leadingIcon)
            }
            
            Text(NSLocalizedString(title, comment: "Button Text"))
            
            if let trailingIcon {
                Image(systemName: trailingIcon)
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
