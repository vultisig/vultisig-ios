//
//  FeeMode.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 27.08.2024.
//

import Foundation

enum FeeMode: CaseIterable, Hashable {
    case safeLow
    case normal
    case fast

    var title: String {
        switch self {
        case .safeLow:
            return "Low"
        case .normal:
            return "Normal"
        case .fast:
            return "Fast"
        }
    }

    var utxoMultiplier: Float {
        switch self {
        case .safeLow:
            return 0.75
        case .normal:
            return 1
        case .fast:
            return 2.5
        }
    }
}
