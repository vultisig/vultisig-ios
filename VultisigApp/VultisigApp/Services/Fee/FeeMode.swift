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
}
