//
//  ToolbarItem+HiddenBackground.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/10/2025.
//

import SwiftUI

extension View {
    /// Helper function to create a toolbar item with conditional shared background visibility
    @ToolbarContentBuilder
    func toolbarItemWithHiddenBackground<Content: View>(
        placement: ToolbarItemPlacement,
        @ViewBuilder content: () -> Content
    ) -> some ToolbarContent {
        if #available(iOS 26.0, macOS 26.0, *) {
            ToolbarItem(placement: placement, content: content)
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement, content: content)
        }
    }
}
