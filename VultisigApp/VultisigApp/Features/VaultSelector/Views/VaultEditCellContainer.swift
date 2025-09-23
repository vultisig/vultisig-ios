//
//  VaultEditCellContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/09/2025.
//

import SwiftUI

struct VaultEditCellContainer<Content: View>: View {
    @Binding var isEditing: Bool
    var content: () -> Content
    
    var body: some View {
        HStack {
            content()
            Icon(
                named: "line-3-horizontal",
                color: Theme.colors.textExtraLight,
                size: 16
            )
            .padding(.trailing, 24)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
        }
        .background(isEditing ? Capsule().fill(Theme.colors.bgSecondary.opacity(0.75)) : nil)
        .padding(.vertical, 4)
        .animation(.easeInOut, value: isEditing)
    }
}
