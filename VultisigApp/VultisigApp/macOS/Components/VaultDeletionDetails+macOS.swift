//
//  VaultDeletionDetails+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(macOS)
import SwiftUI

extension VaultDeletionDetails {
    func getDescriptionText(_ description: String, shouldShrink: Bool = false) -> some View {
        Text(NSLocalizedString(description, comment: ""))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
