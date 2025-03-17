//
//  ElDoritoQuote.swift
//  VoltixApp
//
//  Created by Enrique Souza
//  https://docs.eldorito.club/dkit-by-eldorito/dkit-api/quote-understanding-the-response
//

import Foundation

struct ElDoritoQuote: Codable, Hashable {
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
            let container: KeyedDecodingContainer<ElDoritoQuote.Transaction.CodingKeys> = try decoder.container(keyedBy: ElDoritoQuote.Transaction.CodingKeys.self)
            
            self.from = try container.decode(String.self, forKey: ElDoritoQuote.Transaction.CodingKeys.from)
            self.to = try container.decode(String.self, forKey: ElDoritoQuote.Transaction.CodingKeys.to)
            self.data = try container.decode(String.self, forKey: ElDoritoQuote.Transaction.CodingKeys.data)
            self.value = try container.decode(String.self, forKey: ElDoritoQuote.Transaction.CodingKeys.value)
            self.gasPrice = try container.decode(String.self, forKey: ElDoritoQuote.Transaction.CodingKeys.gasPrice)
            
            let gasValue = try container.decode(Int64.self, forKey: ElDoritoQuote.Transaction.CodingKeys.gas)
            self.gas = gasValue == 0 ? EVMHelper.defaultETHSwapGasUnit : gasValue
        }
    }
    let tx: Transaction
    let expectedBuyAmount: String
    let expectedBuyAmountMaxSlippage: String
}
