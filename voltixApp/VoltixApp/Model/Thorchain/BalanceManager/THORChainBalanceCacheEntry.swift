//
//  THORChainBalanceCacheEntry.swift
//  VoltixApp
//
//  Created by Johnny Luo on 22/3/2024.
//

import Foundation

struct BalanceCacheEntry: Codable {
    let balances: [ThorchainBalance]
    let timestamp: Date
}
