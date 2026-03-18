//
//  THORChainNetworkStatus.swift
//  VultisigApp
//
//  Created by Johnny Luo on 25/7/2024.
//

import Foundation

struct THORChainNetworkStatus: Codable {
    struct resultInfo: Codable {
        struct nodeInfo: Codable {
            let network: String
        }
        let node_info: nodeInfo
    }
    let result: resultInfo
}
