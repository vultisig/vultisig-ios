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

    /// - Parameter detents: iOS presentation detents. Defaults to `.large` — the
    ///   height every existing caller was written against — so passing a smaller
    ///   detent is opt-in for sheets whose content genuinely doesn't fill the
    ///   screen. Ignored on macOS, which sizes sheets by frame rather than detent.
    func sheetStyle(padding: CGFloat? = nil, detents: Set<PresentationDetent> = [.large]) -> some View {
        #if os(iOS)
        self
            .padding(.top, padding ?? 8)
            .presentationBackground(Theme.colors.bgPrimary)
            .presentationDragIndicator(.visible)
            .presentationDetents(detents)
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
