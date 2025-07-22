//
//  PrimaryNavigationButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryNavigationButton<Destination: View>: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let destination: () -> Destination
    
    init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.isLoading = isLoading
        self.type = type
        self.size = size
        self.destination = destination
    }
    
    var body: some View {
        NavigationLink(destination: destination) {
            PrimaryButtonView(
                title: title,
                leadingIcon: leadingIcon,
                trailingIcon: trailingIcon,
                isLoading: isLoading
            )
        }
        .buttonStyle(PrimaryButtonStyle(type: type, size: size))
    }
}
