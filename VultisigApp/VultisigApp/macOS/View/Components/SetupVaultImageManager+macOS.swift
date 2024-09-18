//
//  SetupVaultImageManager+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension SetupVaultImageManager {
    var imageContainer: some View {
        imageContent
            .offset(y: 15)
            .scaleEffect(1.1)
    }
}
#endif
