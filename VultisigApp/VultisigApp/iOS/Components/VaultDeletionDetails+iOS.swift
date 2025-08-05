//
//  VaultDeletionDetails+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(iOS)
import SwiftUI

extension VaultDeletionDetails {
    func getDescriptionText(_ description: String, shouldShrink: Bool = false) -> some View {
        VaultDeletionDescriptionText(description: description, shouldShrink: shouldShrink)
    }
}

private struct VaultDeletionDescriptionText: View {
    
    let description: String
    let shouldShrink: Bool
    
    var body: some View {
        Text(NSLocalizedString(description, comment: ""))
            .font(shouldShrink ? Theme.fonts.caption10 : Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
