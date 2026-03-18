//
//  DefiPositions.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

import SwiftData

@Model
final class DefiPositions: Codable {
    var chain: Chain = Chain.example
    var bonds: [CoinMeta] = []
    var staking: [CoinMeta] = []
    var lps: [CoinMeta] = []

    @Relationship(inverse: \Vault.defiPositions) var vault: Vault?

    enum CodingKeys: String, CodingKey {
        case chain
        case bonds
        case staking
        case lps
    }

    init(
        chain: Chain,
        bonds: [CoinMeta],
        staking: [CoinMeta],
        lps: [CoinMeta]
    ) {
        self.chain = chain
        self.bonds = bonds
        self.staking = staking
        self.lps = lps
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chain = try container.decode(Chain.self, forKey: .chain)
        self.bonds = try container.decode([CoinMeta].self, forKey: .bonds)
        self.staking = try container.decode([CoinMeta].self, forKey: .staking)
        self.lps = try container.decode([CoinMeta].self, forKey: .lps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(bonds, forKey: .bonds)
        try container.encode(staking, forKey: .staking)
        try container.encode(lps, forKey: .lps)
    }
}
