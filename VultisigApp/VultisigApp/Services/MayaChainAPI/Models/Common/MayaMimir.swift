//
//  MayaMimir.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation

struct MayaMimir: Codable {
    let cacaoPoolDepositMaturityBlocks: Int64

    enum CodingKeys: String, CodingKey {
        case cacaoPoolDepositMaturityBlocks = "CACAOPOOLDEPOSITMATURITYBLOCKS"
    }
}
