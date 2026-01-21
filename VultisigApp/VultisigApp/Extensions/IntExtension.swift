//
//  IntExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/06/24.
//

import Foundation

extension Int {
    init?(hex: String) {
        let cleanedHex = hex.stripHexPrefix()
        self.init(cleanedHex, radix: 16)
    }

    var isOdd: Bool {
        self / 2 != 0
    }
}

extension Numeric {
    init(_ pred: Bool) {
        self = if pred { 1 } else { 0 }
    }
}
