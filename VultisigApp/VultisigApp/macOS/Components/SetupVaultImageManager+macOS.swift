//
//  SetupVaultImageManager+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension SetupVaultAnimationManager {
    var imageContainer: some View {
        animation
            .offset(y: 15)
            .scaleEffect(1.1)
    }
}
#endif
