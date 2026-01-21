//
//  ImportVaultShareScreen+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-01.
//

#if os(macOS)
import SwiftUI

extension ImportVaultShareScreen {
    var content: some View {
        view
            .onDrop(of: [.data], isTargeted: $isUploading) { providers -> Bool in
                Task {
                    await backupViewModel.handleOnDrop(providers: providers)
                }
                return true
            }
    }
}
#endif
