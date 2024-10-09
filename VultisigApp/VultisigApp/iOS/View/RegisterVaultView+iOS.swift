//
//  RegisterVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(iOS)
import SwiftUI

extension RegisterVaultView {
    var view: some View {
        VStack {
            image
            content
        }
        .navigationTitle(NSLocalizedString("registerVault", comment: ""))
    }
}
#endif
