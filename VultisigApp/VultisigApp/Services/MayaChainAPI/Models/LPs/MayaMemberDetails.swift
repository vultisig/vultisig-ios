//
//  MayaMemberDetails.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

/// Response from /v2/member/{address}
struct MayaMemberDetails: Codable {
    let pools: [MayaMemberPool]
}

struct MayaMemberPool: Codable {
    let pool: String
    let assetAdded: String
    let assetAddress: String
    let assetPending: String
    let assetWithdrawn: String
    let runeAdded: String
    let runeAddress: String
    let runePending: String
    let runeWithdrawn: String
    let liquidityUnits: String
    let dateFirstAdded: String
    let dateLastAdded: String
}
