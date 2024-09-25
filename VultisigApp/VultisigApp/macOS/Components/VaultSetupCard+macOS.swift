//
//  VaultSetupCard+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension VaultSetupCard {
    var content: some View {
        VStack(spacing: 8) {
            logo
            text
            titleContent
        }
        .offset(y: -24)
    }
}
#endif
