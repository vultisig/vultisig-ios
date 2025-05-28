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

//        enum CodingKeys: String, CodingKey {
//            case from, to, data, value, gasPrice, gas
//        }
//
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            from = try container.decode(String.self, forKey: .from)
//            to = try container.decode(String.self, forKey: .to)
//            data = try container.decode(String.self, forKey: .data)
//            value = try container.decode(String.self, forKey: .value)
//            gasPrice = try? container.decodeIfPresent(String.self, forKey: .gasPrice)
//            let gasValue = try container.decode(Int64.self, forKey: .gas)
//            gas = gasValue == 0 ? EVMHelper.defaultETHSwapGasUnit : gasValue
//        }
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
    func toThorchainSwapQuote() throws -> ThorchainSwapQuote {
        guard let expectedBuyAmount = expectedBuyAmount,
              let memo = memo else {
            throw SwapError.serverError(message: "ElDoritoQuote :: We need the expectedBuyAmount, expiration and memo for this ThorchainSwapQuote")
        }

        return ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedBuyAmount,
            expiry: Int(expiration ?? "0") ?? 0,
            fees: Fees(
                affiliate: fees?.first(where: { $0.type == "affiliate" })?.amount ?? "0",
                asset: fees?.first?.asset ?? "UNKNOWN",
                outbound: fees?.first(where: { $0.type == "outbound" })?.amount ?? "0",
                total: fees?
                    .filter { $0.type == "outbound" || $0.type == "inbound" || $0.type == "affiliate" }
                    .compactMap { Int($0.amount ?? "0") }
                    .reduce(0, +)
                    .description ?? "0"
            ),
            inboundAddress: inboundAddress,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "Converted from ElDoritoQuote",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: totalSlippageBps,
            totalSwapSeconds: estimatedTime?.total,
            warning: warnings?.first ?? "",
            router: nil
        )
    }
}

extension ElDoritoSwapPayload {
    func toOneInchSwapPayload() throws -> OneInchSwapPayload {
        guard let elDoritoTx = quote.tx else {
            throw SwapError.serverError(message: "ElDoritoQuote is missing transaction data")
        }

        let oneInchTx = OneInchQuote.Transaction(
            from: elDoritoTx.from,
            to: elDoritoTx.to,
            data: elDoritoTx.data ?? "",
            value: elDoritoTx.value,
            gasPrice: elDoritoTx.gasPrice ?? "0",
            gas: elDoritoTx.gas ?? .zero
        )

        let oneInchQuote = OneInchQuote(
            dstAmount: quote.expectedBuyAmount ?? "0",
            tx: oneInchTx
        )

        return OneInchSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            toAmountDecimal: toAmountDecimal,
            quote: oneInchQuote
        )
    }
}
