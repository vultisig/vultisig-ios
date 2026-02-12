//
//  SwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

enum SwapProvider: Equatable {
    case thorchain
    case thorchainStagenet
    case thorchainStagenet2
    case mayachain
    case oneinch(Chain)
    case kyberswap(Chain)
    case lifi

    var streamingInterval: Int {
        switch self {
        case .mayachain:
            return 3
        case .thorchain, .thorchainStagenet, .thorchainStagenet2:
            return 1
        default:
            return 0
        }
    }
}
