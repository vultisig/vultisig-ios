//
//  FunctionTransactionType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

enum FunctionTransactionType: Hashable {
    case bond(coin: CoinMeta, node: String?)
    case unbond(node: BondNode)
    case stake(coin: CoinMeta, defaultAutocompound: Bool)
    case unstake(coin: CoinMeta, defaultAutocompound: Bool, availableToUnstake: Decimal? = nil)
    case withdrawRewards(coin: CoinMeta, rewards: Decimal, rewardsCoin: CoinMeta)
    case mint(coin: CoinMeta, yCoin: CoinMeta)
    case redeem(coin: CoinMeta, yCoin: CoinMeta)
    case addLP(position: LPPosition)
    case removeLP(position: LPPosition)

    var coins: [CoinMeta] {
        switch self {
        case .bond(let coin, _):
            return [coin]
        case .unbond(let node):
            return [node.coin]
        case .stake(let coin, _):
            return [coin]
        case .unstake(let coin, _, _):
            return [coin]
        case .withdrawRewards(let coin, _, let rewardsCoin):
            return [coin, rewardsCoin]
        case .mint(let coin, let yCoin):
            return [coin, yCoin]
        case .redeem(let coin, let yCoin):
            return [coin, yCoin]
        case .addLP(let position):
            return [position.coin1, position.coin2]
        case .removeLP(let position):
            return [position.coin1, position.coin2]
        }
    }
}
