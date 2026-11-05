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
    /// 46 tall with a 14pt medium label, filling its parent's width.
    case compact
    /// 46 tall with a 14pt semibold label that the button hugs.
    case compactHug
    /// 46 tall with a 14pt semibold label, filling its parent's width.
    case compactSemibold
    /// 56 tall with a 14pt semibold label, beside a 56 tall field.
    case squared
    /// 32 tall with a 12pt medium label that the button hugs.
    case pill
}
