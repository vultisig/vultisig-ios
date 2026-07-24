//
//  AddressFieldAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct AddressFieldAccessoryButton: View {
    let icon: ImageResource
    /// Per-corner radii. Defaults to a uniform 8; the accessory row overrides
    /// the outer bottom corners to 16 so the stack echoes the card's rounded
    /// bottom edge.
    var cornerRadii = RectangleCornerRadii(
        topLeading: 8,
        bottomLeading: 8,
        bottomTrailing: 8,
        topTrailing: 8
    )
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, color: Theme.colors.textSecondary, size: 20)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(cornerRadii: cornerRadii)
                        .inset(by: 0.5)
                        .fill(Theme.colors.bgSurface1)
                        .stroke(Theme.colors.borderLight)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddressFieldAccessoryButton(icon: .camera) { }
    AddressFieldAccessoryButton(icon: .copies3Filled) { }
}
