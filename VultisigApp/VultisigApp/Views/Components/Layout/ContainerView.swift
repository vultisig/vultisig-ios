//
//  ContainerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct ContainerView<Content: View>: View {
    let content: () -> Content
    
    init(
        @ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        // TODO: - Check relative views
        content()
            .font(Theme.fonts.bodyMMedium)
            .padding(16)
            .background(Theme.colors.bgSecondary)
            .containerStyle()
    }
}
