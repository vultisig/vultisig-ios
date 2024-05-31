//
//  OneInchToken.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.05.2024.
//

import Foundation

struct OneInchToken: Codable, Hashable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURI: String?

    var logoUrl: URL? {
        return logoURI.flatMap { URL(string: $0) }
    }
}
