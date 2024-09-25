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
        Text(NSLocalizedString(description, comment: ""))
            .font(shouldShrink ? .body10Menlo : .body12Menlo)
            .foregroundColor(.neutral0)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
