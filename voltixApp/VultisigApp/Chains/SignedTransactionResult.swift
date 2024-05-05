//
//  SignedTransactionResult.swift
//  VultisigApp
//
//  Created by Johnny Luo on 19/4/2024.
//

import Foundation

struct SignedTransactionResult {
    let rawTransaction: String
    let transactionHash: String
    var signature: String?
}
