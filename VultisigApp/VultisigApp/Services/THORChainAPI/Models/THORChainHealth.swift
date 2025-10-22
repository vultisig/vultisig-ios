//
//  THORChainHealth.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

struct THORChainHealth: Decodable {
    struct HeightInfo: Decodable {
        let height: Int
        let timestamp: Int // seconds since epoch
    }
    let lastThorNode: HeightInfo
}
