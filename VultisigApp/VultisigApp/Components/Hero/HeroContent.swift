//
//  HeroContent.swift
//  VultisigApp
//

import Foundation

/// Content for the dApp signing "hero" region.
///
/// Drives the large, centered display above the transaction summary across the
/// verify → sign → done screens. Three shapes correspond to how much resolved
/// information is available about the action being signed:
///
/// - `.title` — function name only (4byte decoded), no resolved balance change.
///   Used when Blockaid simulation failed or returned no diff.
/// - `.send` — resolved single-sided balance change (Blockaid `.transfer`).
/// - `.swap` — resolved from → to balance change (Blockaid `.swap`).
///
/// Mirrors `BlockaidTransferDisplay` / `BlockaidSwapDisplay` / `EvmCalldataFallback`
/// in the vultisig-windows extension.
enum HeroContent: Hashable {
    case title(text: String, caption: String?)
    case send(title: String?, coin: HeroCoinAmount)
    case swap(title: String?, from: HeroCoinAmount, to: HeroCoinAmount)

    var title: String? {
        switch self {
        case .title(let text, _): return text
        case .send(let title, _): return title
        case .swap(let title, _, _): return title
        }
    }
}

struct HeroCoinAmount: Hashable {
    let amount: String
    let ticker: String
    let logo: String
}
