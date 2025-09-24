//
//  VaultEditCellContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/09/2025.
//

import SwiftUI

struct VaultEditCellContainer<Content: View>: View {
    @Binding var isEditing: Bool
    let rightDragIndicator: Bool
    var content: () -> Content
    
    var body: some View {
        HStack(spacing: 0) {
            icon
                .showIf(!rightDragIndicator)
            content()
            icon
                .showIf(rightDragIndicator)
        }
        .background(isEditing ? Capsule().fill(Theme.colors.bgSecondary.opacity(0.75)) : nil)
        .padding(.vertical, 4)
        .animation(.easeInOut, value: isEditing)
    }
    
    var icon: some View {
        Icon(
            named: "line-3-horizontal",
            color: Theme.colors.textExtraLight,
            size: 16
        )
        .padding(rightDragIndicator ? .trailing : .leading, 16)
        .frame(maxWidth: isEditing ? nil : 0)
        .clipped()
    }
}
