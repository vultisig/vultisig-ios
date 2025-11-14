//
//  FunctionTransactionType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

enum FunctionTransactionType: Hashable {
    case bond(node: String?)
    case unbond(node: BondNode)
    case stake(coin: CoinMeta, defaultAutocompound: Bool)
    case unstake(coin: CoinMeta, defaultAutocompound: Bool)
    case withdrawRewards(coin: CoinMeta, rewards: Decimal, rewardsCoin: CoinMeta)
    case mint(coin: CoinMeta, yCoin: CoinMeta)
    case redeem(coin: CoinMeta, yCoin: CoinMeta)
    case addLP(position: LPPosition)
    case removeLP(position: LPPosition)
}
