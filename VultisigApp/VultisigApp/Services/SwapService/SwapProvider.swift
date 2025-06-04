//
//  SwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

enum SwapProvider: Equatable {
    case thorchain
    case mayachain
    case oneinch(Chain)
    case lifi

    var streamingInterval: Int {
        switch self {
        case .mayachain:
            return 3
        case .thorchain:
            return 1
        default:
            return 0
        }
    }
}
