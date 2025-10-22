//
//  LPPosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation

struct LPPosition: Identifiable, Equatable {
    var id: String { coin1.ticker + coin1.chain.name + coin2.ticker + coin2.chain.name }
    
    let coin1: CoinMeta
    let coin1Amount: Decimal
    let coin2: CoinMeta
    let coin2Amount: Decimal
    let apr: Double
}
