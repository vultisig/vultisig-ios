//
//  SwapKitQuote.swift
//  VultisigApp
//
//  Decodable models for the V3 `/v3/quote` response. `meta.txType` is null at
//  quote stage and only populated by `/v3/swap` — that's why the per-chain
//  payload union lives in `SwapKitSwapResponse`, not here.
//

import Foundation

struct SwapKitQuoteResponse: Codable, Hashable {
    let quoteId: String
    let routes: [SwapKitRoute]
    let providerErrors: [SwapKitProviderError]?
    let error: String?
}

struct SwapKitProviderError: Codable, Hashable {
    let provider: String?
    let errorCode: String?
    let message: String?
}

struct SwapKitRoute: Codable, Hashable {
    let routeId: String
    let providers: [String]
    let sellAsset: String
    let sellAmount: String
    let buyAsset: String
    let expectedBuyAmount: String
    let expectedBuyAmountMaxSlippage: String
    let fees: [SwapKitFee]
    let estimatedTime: SwapKitEstimatedTime?
    let totalSlippageBps: Double?
    let meta: SwapKitQuoteMeta
    /// Optional — Chainflip routes omit this field.
    let expiration: String?
}

struct SwapKitFee: Codable, Hashable {
    let type: String
    let amount: String
    let amountBps: Double?
    let asset: String
    let chain: String
    let protocolName: String

    private enum CodingKeys: String, CodingKey {
        case type
        case amount
        case amountBps
        case asset
        case chain
        // SwapKit's wire field is "protocol", reserved in Swift — alias to
        // `protocolName`.
        case protocolName = "protocol"
    }
}

struct SwapKitEstimatedTime: Codable, Hashable {
    let inbound: Double?
    let swap: Double?
    let outbound: Double?
    let total: Double?
}

struct SwapKitQuoteMeta: Codable, Hashable {
    let assets: [SwapKitAssetMeta]?
    let tags: [String]?
    let priceImpact: Double?
    let approvalAddress: String?
    let streamingInterval: Int?
    let maxStreamingQuantity: Int?
    /// Null at quote stage. Populated only on the `/v3/swap` response — see
    /// `SwapKitSwapResponseMeta`.
    let txType: String?
}

struct SwapKitAssetMeta: Codable, Hashable {
    let asset: String
    let price: Double?
    let image: String?
}
