//
//  MayaNetworkInfo.swift
//  VultisigApp
//
//  Created by AI Assistant on 23/11/2025.
//

import Foundation

/// Response from Midgard /v2/network endpoint
struct MayaNetworkInfo: Decodable {
    let bondingAPY: String?
    let nextChurnHeight: String?

    enum CodingKeys: String, CodingKey {
        case bondingAPY = "bondingAPY"
        case nextChurnHeight = "nextChurnHeight"
    }
}

/// Response from Midgard /v2/health endpoint
struct MayaHealth: Decodable {
    let lastMayaNode: LastNodeInfo

    enum CodingKeys: String, CodingKey {
        case lastMayaNode = "lastMayaNode"
    }

    struct LastNodeInfo: Decodable {
        let height: Int
        let timestamp: Int

        enum CodingKeys: String, CodingKey {
            case height
            case timestamp
        }
    }
}
