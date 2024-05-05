//
//  TransactionStatus.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class UTXOTransactionStatus: Codable {
    let confirmed: Bool
    let block_height: Int?
    let block_hash: String?
    let block_time: Int?
}
