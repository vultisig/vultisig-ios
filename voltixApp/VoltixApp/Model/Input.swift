//
//  Input.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class Input: Codable {
    let txid: String
    let vout: Int
    let prevout: PreviousOutput?
    let sequence: UInt32
    let scriptsig: String?
    let scriptsig_asm: String?
    let witness: [String]?
    let is_coinbase: Bool?
}
