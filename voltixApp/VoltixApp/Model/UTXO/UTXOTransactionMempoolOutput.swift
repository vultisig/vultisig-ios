//
//  Output.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class UTXOTransactionMempoolOutput: Codable {
    let scriptpubkey: String
    let scriptpubkey_asm: String
    let scriptpubkey_type: String
    let scriptpubkey_address: String?
    let value: Int
}
