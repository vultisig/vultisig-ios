//
//  Rate.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.08.2024.
//

import Foundation

struct Rate: Hashable {
    static let identity: Rate = .init(fiat: "", crypto: "", value: 1)
    static func identifier(fiat: String, crypto: String) -> String {
        return "\(fiat.lowercased())-\(crypto.lowercased())"
    }

    let id: String
    let fiat: String
    let crypto: String
    let value: Double

    init(fiat: String, crypto: String, value: Double) {
        self.id = Rate.identifier(fiat: fiat, crypto: crypto)
        self.fiat = fiat
        self.crypto = crypto
        self.value = value
    }

    init(object: DatabaseRate) {
        self.id = object.id
        self.fiat = object.fiat
        self.crypto = object.crypto
        self.value = object.value
    }

    func mapToObject() -> DatabaseRate {
        return DatabaseRate(id: id, fiat: fiat, crypto: crypto, value: value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(value)
    }
}
