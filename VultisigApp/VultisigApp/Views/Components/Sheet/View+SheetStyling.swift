//
//  View+PlatformSheetSize.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

extension View {
    func applySheetSize(_ width: CGFloat = 700, _ height: CGFloat = 650) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self
        #endif
    }
    
    func sheetStyle(padding: CGFloat? = nil) -> some View {
        #if os(iOS)
        self
            .padding(.top, padding ?? 8)
            .presentationBackground(Theme.colors.bgPrimary)
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        #else
        self
        #endif
    }
}
