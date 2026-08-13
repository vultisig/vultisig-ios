//
//  LimitSwapFocusField.swift
//  VultisigApp
//

import SwiftUI

/// The limit form's editable fields, as focus identities.
///
/// A `.keyboard` toolbar is NOT scoped to the TextField it is attached to — it is
/// merged across every view in the presented hierarchy. The flat layout renders
/// the price card and the Sell row at the same time, so per-field accessories
/// would collide and the Sell percentage buttons could surface while the *price*
/// is being edited (tapping one would then mutate the sell amount behind the
/// user's back). The parent therefore owns ONE keyboard toolbar and switches its
/// content on the focused field, which this enum names.
enum LimitFocusField: Hashable {
    /// The asset-terms target price (canonical `draft.targetPrice`).
    case assetPrice
    /// The USD-denominated target price — only rendered in USD mode.
    case usdPrice
    /// The Sell amount — the only balance-derived field, so the only one that
    /// gets the percentage buttons.
    case sellAmount
    /// The Buy amount. Editable, but deliberately WITHOUT the percentage
    /// buttons: those are percentages of the source balance, which is a Sell
    /// concept — offering them here would apply a share of what you hold to the
    /// side describing what you want.
    case buyAmount
}

/// Scroll targets used to lift the focused field clear of the iOS keyboard.
///
/// Coarser than `LimitFocusField` by exactly one step: the asset-terms and USD
/// price fields are two representations of one number occupying one row, so they
/// share an anchor. Every anchor is attached to a compact ROW, never to the card
/// around it — a card taller than the keyboard-reduced viewport cannot be brought
/// into view without pushing one of its ends off the screen.
enum LimitScrollAnchor: Hashable {
    case sell
    case buy
    case price

    init?(focus: LimitFocusField?) {
        switch focus {
        case .sellAmount:
            self = .sell
        case .buyAmount:
            self = .buy
        case .assetPrice, .usdPrice:
            self = .price
        case nil:
            return nil
        }
    }
}
