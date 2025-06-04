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
    var quoteId: String
    var routes: [ElDoritoQuote]
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
    var fees: [Fee]?
    var tx: Transaction?
    let estimatedTime: EstimatedTime?
    let totalSlippageBps: Int?
    let legs: [Leg]?
    let warnings: [String]?
    let meta: Meta?
    
    struct Transaction: Codable, Hashable {
        let from: String
        let to: String
        let data: String?
        let value: String
        var gasPrice: String?
        var gas: Int64?
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
        let approvalAddress: String?
    }
    
    struct Asset: Codable, Hashable {
        let asset: String?
        let price: Double?
        let image: String?
    }
}

extension ElDoritoQuote {
    func toOneInchQuote() throws -> OneInchQuote {
        
        guard let elDoritoTx = self.tx else {
            throw SwapError.serverError(message: "ElDoritoQuote is missing transaction data")
        }
        
        return OneInchQuote(
            dstAmount: self.expectedBuyAmount ?? "0",
            tx: elDoritoTx.toOneInchQuoteTransaction()
        )
    }
}

extension ElDoritoQuote.Transaction {
    func toOneInchQuoteTransaction() -> OneInchQuote.Transaction {
        OneInchQuote.Transaction(
            from: self.from,
            to: self.to,
            data: self.data ?? "",
            value: self.value,
            gasPrice: self.gasPrice ?? "0",
            gas: self.gas ?? Int64(0)
        )
    }
}