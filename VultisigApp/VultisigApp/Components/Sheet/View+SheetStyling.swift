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

    /// `fullScreen` is only meaningful on iOS and is intended for content
    /// presented via `crossPlatformSheet(isPresented:fullScreen:)`, which on
    /// iOS swaps the `.sheet` for a `.fullScreenCover`. In that mode the drag
    /// indicator and detents are meaningless (a cover is already edge-to-edge),
    /// so they are dropped. The macOS path is unchanged.
    func sheetStyle(padding: CGFloat? = nil, fullScreen: Bool = false) -> some View {
        #if os(iOS)
        self
            .padding(.top, padding ?? 8)
            .presentationBackground(Theme.colors.bgPrimary)
            .presentationDragIndicator(fullScreen ? .hidden : .visible)
            .applyLargeDetentIfNeeded(fullScreen: fullScreen)
        #else
        self
            .background(Theme.colors.bgPrimary)
        #endif
    }

    #if os(iOS)
    /// A `.fullScreenCover` already fills the screen, so attaching
    /// `.presentationDetents([.large])` is both redundant and, on a cover,
    /// inert — only apply the detent for the standard (sheet) presentation.
    @ViewBuilder
    fileprivate func applyLargeDetentIfNeeded(fullScreen: Bool) -> some View {
        if fullScreen {
            self
        } else {
            self.presentationDetents([.large])
        }
    }
    #endif

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
