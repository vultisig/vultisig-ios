//
//  Rate.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import SwiftData

@Model
final class Rate {

    static func identifier(fiat: String, crypto: String) -> String {
        return "\(fiat)-\(crypto)"
    }

    @Attribute(.unique) var id: String
    
    let fiat: String
    let crypto: String
    var value: Double

    init(fiat: String, crypto: String, value: Double) {
        self.id = Rate.identifier(fiat: fiat, crypto: crypto)
        self.fiat = fiat
        self.crypto = crypto
        self.value = value
    }
}
