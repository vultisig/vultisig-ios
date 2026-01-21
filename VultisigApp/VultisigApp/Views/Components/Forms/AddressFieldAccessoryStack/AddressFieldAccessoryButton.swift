//
//  AddressFieldAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct AddressFieldAccessoryButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textSecondary, size: 20)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .inset(by: 0.5)
                        .fill(Theme.colors.bgSurface1)
                        .stroke(Theme.colors.borderLight)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddressFieldAccessoryButton(icon: "camera") { }
    AddressFieldAccessoryButton(icon: "copy") { }
}
