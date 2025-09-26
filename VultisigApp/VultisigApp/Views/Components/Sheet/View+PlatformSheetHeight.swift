//
//  View+PlatformSheetHeight.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

extension View {
    func applySheetHeight(_ height: CGFloat = 650) -> some View {
        #if os(macOS)
        self.frame(height: height)
        #else
        self
        #endif
    }
}
