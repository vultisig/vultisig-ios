//
//  OneInchQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct OneInchQuote: Codable {
    struct Transaction: Codable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64
    }
    let dstAmount: String
    let tx: Transaction
}
