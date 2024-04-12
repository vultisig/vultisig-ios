//
//  Input.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class UTXOTransactionMempoolInput: Codable {
    let txid: String
    let vout: Int
    let prevout: UTXOTransactionMempoolPreviousOutput?
    let scriptsig: String?
    let scriptsig_asm: String?
}
