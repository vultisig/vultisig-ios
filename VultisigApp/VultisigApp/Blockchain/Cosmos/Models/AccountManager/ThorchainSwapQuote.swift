//
//  ThorchainSwapQuote.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 03.04.2024.
//

import Foundation

struct ThorchainSwapQuote: Codable, Hashable {
    let dustThreshold: String?
    let expectedAmountOut: String
    let expiry: Int
    let fees: Fees
    let inboundAddress: String?
    let inboundConfirmationBlocks: Int?
    let inboundConfirmationSeconds: Int?
    let memo: String
    let notes: String
    let outboundDelayBlocks: Int
    let outboundDelaySeconds: Int
    let recommendedMinAmountIn: String
    let slippageBps: Int?
    let totalSwapSeconds: Int?
    let warning: String
    let router: String?

    enum CodingKeys: String, CodingKey {
        case dustThreshold = "dust_threshold"
        case expectedAmountOut = "expected_amount_out"
        case expiry
        case fees
        case inboundAddress = "inbound_address"
        case inboundConfirmationBlocks = "inbound_confirmation_blocks"
        case inboundConfirmationSeconds = "inbound_confirmation_seconds"
        case memo
        case notes
        case outboundDelayBlocks = "outbound_delay_blocks"
        case outboundDelaySeconds = "outbound_delay_seconds"
        case recommendedMinAmountIn = "recommended_min_amount_in"
        case slippageBps = "slippage_bps"
        case totalSwapSeconds = "total_swap_seconds"
        case warning
        case router
    }
}

struct Fees: Codable, Hashable {
    let affiliate: String
    let asset: String
    let outbound: String
    let total: String
}
