//
//  CosmosSignature.swift
//  VultisigApp
//
//  Created by Johnny Luo on 19/4/2024.
//

import Foundation

struct CosmosSignature: Codable {
    let mode: String
    let tx_bytes: String

    func getTransactionHash() -> String {
        return Data(base64Encoded: tx_bytes)?.sha256().toHexString().uppercased() ?? ""
    }
}

