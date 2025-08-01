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
    @Environment(\.theme) private var theme
    
    var body: some View {
        Text(NSLocalizedString(description, comment: ""))
            .font(shouldShrink ? theme.fonts.caption10 : .body12Menlo)
            .foregroundColor(.neutral0)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
