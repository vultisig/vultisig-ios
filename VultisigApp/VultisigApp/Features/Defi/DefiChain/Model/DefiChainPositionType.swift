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
        }
    }
}
