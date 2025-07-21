//
//  NavigationIconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct NavigationIconButton<Destination: View>: View {
    let icon: String
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let destination: () -> Destination
    
    init(
        icon: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.icon = icon
        self.isLoading = isLoading
        self.type = type
        self.size = size
        self.destination = destination
    }
    
    var body: some View {
        NavigationLink(destination: destination) {
            VultiIconButtonView(
                icon: icon,
                isLoading: isLoading
            )
        }
        .buttonStyle(PrimaryButtonStyle(type: type, size: size))
    }
}
