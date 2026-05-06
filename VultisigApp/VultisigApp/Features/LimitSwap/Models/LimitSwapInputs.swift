//
//  LimitSwapInputs.swift
//  VultisigApp
//

import BigInt
import Foundation

struct LimitSwapInputs: Equatable {
    let sourceAsset: String
    let sourceAmount: BigInt
    let sourceDecimals: Int
    let targetAsset: String
    let destAddress: String
    let targetPrice: Decimal
    let expiryHours: Int
    let affiliate: String
    let affiliateBps: String
}
