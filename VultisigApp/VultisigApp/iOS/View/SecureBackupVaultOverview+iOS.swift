//
//  SecureBackupVaultOverview+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(iOS)
import SwiftUI

extension SecureBackupVaultOverview {
    var container: some View {
        content
            .navigationBarBackButtonHidden(true)
    }
}
#endif
