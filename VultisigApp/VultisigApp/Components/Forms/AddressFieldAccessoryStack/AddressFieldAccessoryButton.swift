//
//  AddressFieldAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct AddressFieldAccessoryButton: View {
    let icon: ImageResource
    /// Per-corner radii. Defaults to a uniform `sm`; the accessory row overrides
    /// the two outer bottom corners to `lg` so the row's outer edge reads as one
    /// rounded block rather than three separate tiles.
    var cornerRadii = RectangleCornerRadii(
        topLeading: Theme.radius.sm.points,
        bottomLeading: Theme.radius.sm.points,
        bottomTrailing: Theme.radius.sm.points,
        topTrailing: Theme.radius.sm.points
    )
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, color: Theme.colors.textSecondary, size: 20)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: Theme.radius.sm.style)
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
