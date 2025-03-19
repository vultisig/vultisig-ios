//
//  ElDoritoQuote.swift
//  VoltixApp
//
//  Created by Enrique Souza
//  https://docs.eldorito.club/dkit-by-eldorito/dkit-api/quote-understanding-the-response
//

import Foundation
import BigInt

struct ElDoritoResponse: Codable, Hashable {
    let quoteId: String
    let routes: [ElDoritoQuote]
}

struct ElDoritoQuote: Codable, Hashable {
    let providers: [String]?
    let sellAsset: String?
    let sellAmount: String?
    let buyAsset: String?
    let expectedBuyAmount: String?
    let expectedBuyAmountMaxSlippage: String?
    let sourceAddress: String?
    let destinationAddress: String?
    let targetAddress: String?
    let inboundAddress: String?
    let expiration: String?
    let memo: String?
    let fees: [Fee]?
    let tx: Transaction?
    let estimatedTime: EstimatedTime?
    let totalSlippageBps: Int?
    let legs: [Leg]?
    let warnings: [String]?
    let meta: Meta?
    
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
    
    struct Fee: Codable, Hashable {
        let type: String?
        let amount: String?
        let asset: String?
        let chain: String?
        let `protocol`: String?
    }
    
    struct EstimatedTime: Codable, Hashable {
        let inbound: Int?
        let swap: Int?
        let outbound: Int?
        let total: Int?
    }
    
    struct Leg: Codable, Hashable {
        let provider: String?
        let sellAsset: String?
        let sellAmount: String?
        let buyAsset: String?
        let buyAmount: String?
        let buyAmountMaxSlippage: String?
        let fees: [Fee]?
    }
    
    struct Meta: Codable, Hashable {
        let priceImpact: Double?
        let assets: [Asset]?
        let affiliate: String?
        let affiliateFee: String?
        let tags: [String]?
        let txType: String?
    }
    
    struct Asset: Codable, Hashable {
        let asset: String?
        let price: Double?
        let image: String?
    }
}

extension ElDoritoQuote {
    func toThorchainSwapQuote() throws -> ThorchainSwapQuote {
        guard let expectedBuyAmount = expectedBuyAmount,
              let expiration = expiration,
              let memo = memo else {
            throw SwapError.serverError(message: "ElDoritoQuote :: We need the expectedBuyAmount, expiration and memo for this ThorchainSwapQuote")
        }
        
        return ThorchainSwapQuote(
            dustThreshold: nil, // No direct mapping, setting as nil
            expectedAmountOut: expectedBuyAmount,
            expiry: Int(expiration) ?? 0,
            fees: Fees(
                affiliate: fees?.first(where: { $0.type == "affiliate" })?.amount ?? "0",
                asset: fees?.first?.asset ?? "UNKNOWN",
                outbound: fees?.first(where: { $0.type == "outbound" })?.amount ?? "0",
                total: fees?
                    .compactMap { fee in
                        if let amount = fee.amount, let intAmount = Int(amount) {
                            return intAmount
                        }
                        return nil
                    }
                    .reduce(0, +).description ?? "0"
            ),
            inboundAddress: inboundAddress,
            inboundConfirmationBlocks: nil, // Not provided in ElDoritoQuote
            inboundConfirmationSeconds: nil, // Not provided in ElDoritoQuote
            memo: memo,
            notes: "Converted from ElDoritoQuote", // Adding a note
            outboundDelayBlocks: 0, // Not available, setting to 0
            outboundDelaySeconds: 0, // Not available, setting to 0
            recommendedMinAmountIn: "0", // Not available, setting to "0"
            slippageBps: totalSlippageBps,
            totalSwapSeconds: estimatedTime?.total,
            warning: warnings?.first ?? "",
            router: nil // Not provided in ElDoritoQuote
        )
    }
}

extension ElDoritoQuote {
    func toOneInchSwapPayload(fromCoin: Coin, toCoin: Coin) throws -> OneInchQuote {
        guard
            let expectedBuyAmount = expectedBuyAmount,
            let tx = tx else {
            throw SwapError.serverError(message: "ElDoritoQuote :: Missing required fields (sellAmount, expectedBuyAmount, tx) for OneInchSwapPayload")
        }
        
        return OneInchQuote(
            dstAmount: expectedBuyAmount,
            tx: OneInchQuote.Transaction(
                from: tx.from,
                to: tx.to,
                data: tx.data,
                value: tx.value,
                gasPrice: tx.gasPrice,
                gas: tx.gas
            )
        )
    }
}
