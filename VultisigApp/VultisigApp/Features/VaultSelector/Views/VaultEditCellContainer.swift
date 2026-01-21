//
//  VaultEditCellContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/09/2025.
//

import SwiftUI

struct VaultEditCellContainer<Content: View>: View {
    @Binding var isEditing: Bool
    let showDragIndicator: Bool
    var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            icon
                .showIf(showDragIndicator)
            content()
        }
        .background(isEditing ? Capsule().fill(Theme.colors.bgSurface1.opacity(0.75)) : nil)
        .padding(.vertical, 4)
        .animation(.easeInOut, value: isEditing)
    }

    var icon: some View {
        Icon(
            named: "line-3-horizontal",
            color: Theme.colors.textTertiary,
            size: 16
        )
        .padding(.leading, 16)
        .frame(maxWidth: isEditing ? nil : 0)
        .clipped()
    }
}
