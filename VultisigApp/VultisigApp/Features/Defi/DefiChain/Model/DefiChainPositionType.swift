//
//  THORChainPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

enum DefiChainPositionType: String, CaseIterable, Hashable, Identifiable {
    case bond
    case stake
    case liquidityPool
    case governance
    /// Yield-vault deposits (Kamino Earn on Solana). Selectable like bond /
    /// stake / LP, but its elements are curated vaults rather than coins, so it
    /// has no `selectionIndex` bucket — see `DefiChainPositionType.selectionIndex`.
    case earn

    var id: String { rawValue }

    var segmentedControlTitle: String {
        switch self {
        case .bond:
            "bonded".localized
        case .stake:
            "staked".localized
        case .liquidityPool:
            "lps".localized
        case .governance:
            "governance".localized
        case .earn:
            "earn".localized
        }
    }

    var sectionTitle: String {
        switch self {
        case .bond:
            "bond".localized
        case .stake:
            "stake".localized
        case .liquidityPool:
            "liquidityPools".localized
        case .governance:
            "governance".localized
        case .earn:
            "earn".localized
        }
    }

    /// Bucket index of this position type inside the picker's `selection`, fixed
    /// by the shape of the persisted `DefiPositions` record. Deliberately
    /// independent of the catalog's section order, which is presentational:
    /// deriving it from the catalog would silently file a selection under the
    /// wrong position type if a section were ever reordered or omitted.
    ///
    /// `nil` means "not a `DefiPositions` bucket". Governance is not selectable
    /// at all; Earn is selectable but its enablement lives on `KaminoPosition`,
    /// so neither has a coin bucket.
    var selectionIndex: Int? {
        switch self {
        case .bond:
            0
        case .stake:
            1
        case .liquidityPool:
            2
        case .governance, .earn:
            nil
        }
    }
}
