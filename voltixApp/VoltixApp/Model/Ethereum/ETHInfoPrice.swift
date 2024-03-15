//
//  Price.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class ETHInfoPrice: Codable {
    let rate: Double
    let diff: Double
    let diff7d: Double
    let ts: Int
    let marketCapUsd: Double
    let availableSupply: Double
    let volume24h: Double
}
