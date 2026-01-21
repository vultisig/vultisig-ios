//
//  NavigationBackButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct NavigationBackButton: View {
    var tint: Color = Theme.colors.textPrimary

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ToolbarButton(image: "chevron-right", action: { dismiss() })
            .rotationEffect(.radians(.pi))
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBackButton()
    }
}
