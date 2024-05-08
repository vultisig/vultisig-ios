//
//  OneInchQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct OneInchQuote: Codable {
    struct Token: Codable {
        let address: String
        let symbol: String
        let name: String
        let decimals: Int
        let logoURI: String
        let domainVersion: String
        let eip2612: Bool
        let isFoT: Bool
        let tags: [String]
    }
    struct Transaction: Codable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64
    }
    let fromToken: Token
    let toToken: Token
    let toAmount: String
    let tx: Transaction
}
