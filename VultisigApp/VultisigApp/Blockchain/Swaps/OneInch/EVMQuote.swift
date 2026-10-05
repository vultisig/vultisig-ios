//
//  EVMQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation

struct EVMQuote: Codable, Hashable {
    struct Transaction: Codable, Hashable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64
        let swapFee: String?
        let swapFeeTokenContract: String
        /// The provider's own charge, itemized apart from the affiliate fee. LI.FI
        /// EVM quotes keep it inside `swapFee`; LI.FI Solana quotes state it in
        /// addition to `swapFee`. Display only: never part of the signed payload.
        let protocolFee: String?
        let protocolFeeTokenContract: String

        init(
            from: String, to: String, data: String, value: String, gasPrice: String, gas: Int64,
            swapFee: String? = nil, swapFeeTokenContract: String = "",
            protocolFee: String? = nil, protocolFeeTokenContract: String = ""
        ) {
            self.from = from
            self.to = to
            self.data = data
            self.value = value
            self.gasPrice = gasPrice
            self.gas = gas
            self.swapFee = swapFee
            self.swapFeeTokenContract = swapFeeTokenContract
            self.protocolFee = protocolFee
            self.protocolFeeTokenContract = protocolFeeTokenContract
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<EVMQuote.Transaction.CodingKeys> = try decoder.container(keyedBy: EVMQuote.Transaction.CodingKeys.self)

            self.from = try container.decode(String.self, forKey: EVMQuote.Transaction.CodingKeys.from)
            self.to = try container.decode(String.self, forKey: EVMQuote.Transaction.CodingKeys.to)
            self.data = try container.decode(String.self, forKey: EVMQuote.Transaction.CodingKeys.data)
            self.value = try container.decode(String.self, forKey: EVMQuote.Transaction.CodingKeys.value)
            self.gasPrice = try container.decode(String.self, forKey: EVMQuote.Transaction.CodingKeys.gasPrice)

            let gasValue = try container.decode(Int64.self, forKey: EVMQuote.Transaction.CodingKeys.gas)
            self.gas = gasValue == 0 ? EVMHelper.defaultETHSwapGasUnit : gasValue

            self.swapFee = try container.decodeIfPresent(String.self, forKey: EVMQuote.Transaction.CodingKeys.swapFee)
            self.swapFeeTokenContract = try container.decodeIfPresent(String.self, forKey: EVMQuote.Transaction.CodingKeys.swapFeeTokenContract) ?? ""
            self.protocolFee = try container.decodeIfPresent(String.self, forKey: EVMQuote.Transaction.CodingKeys.protocolFee)
            self.protocolFeeTokenContract = try container.decodeIfPresent(String.self, forKey: EVMQuote.Transaction.CodingKeys.protocolFeeTokenContract) ?? ""
        }
    }
    let dstAmount: String
    let tx: Transaction
}
