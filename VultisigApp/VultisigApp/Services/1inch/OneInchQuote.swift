//
//  OneInchQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct OneInchQuote: Codable, Hashable {
    struct Transaction: Codable, Hashable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64

        init(from: String, to: String, data: String, value: String, gasPrice: String, gas: Int64) {
            self.from = from
            self.to = to
            self.data = data
            self.value = value
            self.gasPrice = gasPrice
            self.gas = gas
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<OneInchQuote.Transaction.CodingKeys> = try decoder.container(keyedBy: OneInchQuote.Transaction.CodingKeys.self)
            
            self.from = try container.decode(String.self, forKey: OneInchQuote.Transaction.CodingKeys.from)
            self.to = try container.decode(String.self, forKey: OneInchQuote.Transaction.CodingKeys.to)
            self.data = try container.decode(String.self, forKey: OneInchQuote.Transaction.CodingKeys.data)
            self.value = try container.decode(String.self, forKey: OneInchQuote.Transaction.CodingKeys.value)
            self.gasPrice = try container.decode(String.self, forKey: OneInchQuote.Transaction.CodingKeys.gasPrice)
            
            let gasValue = try container.decode(Int64.self, forKey: OneInchQuote.Transaction.CodingKeys.gas)
            self.gas = gasValue == 0 ? EVMHelper.defaultETHSwapGasUnit : gasValue
        }
    }
    let dstAmount: String
    let tx: Transaction
}
