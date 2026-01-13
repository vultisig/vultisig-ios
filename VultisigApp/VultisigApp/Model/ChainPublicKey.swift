//
//  ChainPublicKey.swift
//  VultisigApp
//
//  Created by Johnny Luo on 25/11/2025.
//

import Foundation
import SwiftData

@Model
final class ChainPublicKey {
    @Attribute(.unique) var id: String
    var chain: Chain
    var publicKeyHex: String
    var isEddsa: Bool
    var derivationType: DerivationType?

    @Relationship(inverse: \Vault.chainPublicKeys) var vault: Vault?

    init(chain: Chain, publicKeyHex: String, isEddsa: Bool, derivationType: DerivationType? = nil) {
        self.id = "\(chain.name)-\(publicKeyHex)"
        self.chain = chain
        self.publicKeyHex = publicKeyHex
        self.isEddsa = isEddsa
        self.derivationType = derivationType
    }
}
