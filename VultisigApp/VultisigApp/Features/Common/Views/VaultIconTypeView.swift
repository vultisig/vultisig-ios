//
//  VaultIconTypeView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultIconTypeView: View {
    let isFastVault: Bool
    var usesFilledIcon = false

    var iconName: ImageResource {
        if usesFilledIcon {
            return isFastVault ? .boltFilled : .shieldFilled
        }
        return isFastVault ? .bolt : .shield
    }

    var iconColor: Color {
        isFastVault ? Theme.colors.alertWarning : Theme.colors.bgButtonPrimary
    }

    var body: some View {
        Icon(iconName, color: iconColor, size: 16)
    }
}

#Preview {
    VaultIconTypeView(isFastVault: false)
    VaultIconTypeView(isFastVault: true)
}
