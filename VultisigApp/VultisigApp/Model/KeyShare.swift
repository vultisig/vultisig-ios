//
//  KeyShare.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class KeyShare: Codable {
    let pubkey: String
    let keyshare: String

    init(pubkey: String, keyshare: String) {
        self.pubkey = pubkey
        self.keyshare = keyshare
    }
}
