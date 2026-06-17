//
//  SwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

enum SwapProvider: Equatable {
    case thorchain
    case thorchainChainnet
    case thorchainStagenet
    case mayachain
    case oneinch(Chain)
    case kyberswap(Chain)
    case lifi
    case swapkit

    var streamingInterval: Int {
        switch self {
        case .mayachain:
            return 3
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return 0
        default:
            return 0
        }
    }

    /// Whether this provider can send the swapped funds to an external recipient.
    /// Only THORChain/Maya honour it: the user-supplied address becomes the swap
    /// memo's `destination`, so the node delivers the output there
    /// (`SwapService.fetchCrossChainQuote`). The aggregator routes (1inch /
    /// KyberSwap / LI.FI / SwapKit) build the swap tx with the user's OWN address
    /// and silently ignore the recipient — picking one while an external
    /// recipient is set would send funds to self while the verify screen shows
    /// the external address. So they're excluded from quote ranking whenever an
    /// external recipient is set.
    var honorsExternalRecipient: Bool {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return true
        case .oneinch, .kyberswap, .lifi, .swapkit:
            return false
        }
    }
}
