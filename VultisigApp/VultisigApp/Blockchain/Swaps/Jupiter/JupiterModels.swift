//
//  JupiterModels.swift
//  VultisigApp
//
//  Codable request/response models for Jupiter's Solana swap API
//  (`/jup/swap/v1/quote` + `/jup/swap/v1/swap`), proxied through
//  `api.vultisig.com`.
//

import Foundation

/// Quote query parameters for `GET /swap/v1/quote`.
struct JupiterQuoteParams {
    let inputMint: String
    let outputMint: String
    /// Input amount in raw base units of the input mint.
    let amount: String
    let slippageBps: Int
    /// Affiliate fee in basis points. Only attached when greater than zero so a
    /// fully-discounted user (or a fee-disabled path) doesn't request a fee
    /// account Jupiter would then require.
    let platformFeeBps: Int?

    var queryItems: [String: Any] {
        var items: [String: Any] = [
            "inputMint": inputMint,
            "outputMint": outputMint,
            "amount": amount,
            "slippageBps": slippageBps
        ]
        if let platformFeeBps, platformFeeBps > 0 {
            items["platformFeeBps"] = platformFeeBps
        }
        return items
    }
}

/// Subset of Jupiter's `/quote` response we read. The full response is also
/// forwarded verbatim to `/swap` (see `JupiterService`), so this struct only
/// needs the fields used for ranking, fee accounting, and validation.
struct JupiterQuoteResponse: Decodable {
    let outputMint: String
    /// Output amount in raw base units of the output mint (gross of platform fee).
    let outAmount: String
    let platformFee: PlatformFee?
    let routePlan: [RoutePlanStep]

    struct PlatformFee: Decodable {
        let amount: String?
        let feeBps: Int?
    }

    struct RoutePlanStep: Decodable {
        let swapInfo: SwapInfo

        struct SwapInfo: Decodable {
            let feeAmount: String?
            let feeMint: String?
        }
    }
}

/// `/swap` response. We only need the base64-encoded Solana wire transaction;
/// the signer refreshes its blockhash in place before signing.
struct JupiterSwapResponse: Decodable {
    let swapTransaction: String
}
