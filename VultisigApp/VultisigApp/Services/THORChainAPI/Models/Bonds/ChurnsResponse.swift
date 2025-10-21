//
//  ChurnsResponse.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

/// Response model for THORChain churns history
/// Endpoint: GET https://midgard.ninerealms.com/v2/churns
struct ChurnsResponse: Decodable {
    let date: String  // Unix timestamp in nanoseconds
    let pool: String?
    let addedNodes: [String]?
    let removedNodes: [String]?

    enum CodingKeys: String, CodingKey {
        case date
        case pool
        case addedNodes = "added_nodes"
        case removedNodes = "removed_nodes"
    }
}
