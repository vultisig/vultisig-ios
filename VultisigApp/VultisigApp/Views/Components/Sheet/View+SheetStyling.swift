//
//  View+PlatformSheetSize.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

extension View {
    func applySheetSize(_ width: CGFloat = 700, _ height: CGFloat? = 550) -> some View {
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
            .background(Theme.colors.bgPrimary)
        #endif
    }

    @ViewBuilder
    func presentationSizingFitted() -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            self.presentationSizing(.fitted)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
