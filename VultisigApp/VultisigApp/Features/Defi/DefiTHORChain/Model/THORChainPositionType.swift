//
//  THORChainPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

enum THORChainPositionType: String, CaseIterable, Hashable, Identifiable {
    case bond
    case stake
    case liquidityPool
    
    var id: String { rawValue }
    
    var segmentedControlTitle: String {
        switch self {
        case .bond:
            "bonded".localized
        case .stake:
            "staked".localized
        case .liquidityPool:
            "lps".localized
        }
    }
}
