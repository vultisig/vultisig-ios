//
//  BackupVaultNowView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(macOS)
import SwiftUI

extension BackupVaultNowView {
    var container: some View {
        content
            .padding(.vertical, 40)
    }
}
#endif
