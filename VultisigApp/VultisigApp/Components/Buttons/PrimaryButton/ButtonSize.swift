//
//  ButtonSize.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

enum ButtonSize {
    case medium
    case small
    /// Same vertical size as `.small` but with zero horizontal padding so
    /// the button stretches to its parent's available width. Used by row
    /// layouts that already gutter the buttons themselves (e.g. the
    /// Cosmos staking position-card action row).
    case smallFixed
    case mini
    case squared
}
