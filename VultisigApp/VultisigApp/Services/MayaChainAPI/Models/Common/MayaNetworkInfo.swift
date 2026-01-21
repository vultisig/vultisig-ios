//
//  MayaNetworkInfo.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

/// Response from Midgard /v2/network endpoint
struct MayaNetworkInfo: Decodable {
    let bondingAPY: String?
    let nextChurnHeight: String?
    let totalPooledRune: String?  // Total CACAO in the pool (in atomic units)
    let liquidityAPY: String?     // CACAO pool APY

    enum CodingKeys: String, CodingKey {
        case bondingAPY
        case nextChurnHeight
        case totalPooledRune
        case liquidityAPY
    }
}

/// Response from Midgard /v2/health endpoint
struct MayaHealth: Decodable {
    let lastMayaNode: LastNodeInfo

    enum CodingKeys: String, CodingKey {
        case lastMayaNode = "lastThorNode"
    }

    struct LastNodeInfo: Decodable {
        let height: Int64
        let timestamp: Int

        enum CodingKeys: String, CodingKey {
            case height
            case timestamp
        }
    }
}
