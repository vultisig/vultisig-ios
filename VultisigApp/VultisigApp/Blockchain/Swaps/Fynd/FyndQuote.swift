//
//  FyndQuote.swift
//  VultisigApp
//
//  Wire models for Propeller Heads' Fynd quote API (`POST /v1/{chain}/quote`).
//  Field names follow the Fynd OpenAPI schema (snake_case).
//

import Foundation

struct FyndQuoteRequest: Encodable, Equatable {
    struct Order: Encodable, Equatable {
        let tokenIn: String
        let tokenOut: String
        let amount: String
        let side: String
        let sender: String
        let receiver: String

        enum CodingKeys: String, CodingKey {
            case tokenIn = "token_in"
            case tokenOut = "token_out"
            case amount, side, sender, receiver
        }
    }

    /// The app only names the fee and its receiver. The `api.vultisig.com/fynd`
    /// proxy pins `max_contribution` to 0, sets the deadline, sends Fynd an empty
    /// signature, then signs the returned quote with the receiver key and
    /// patches the signature into the calldata.
    struct ClientFeeParams: Encodable, Equatable {
        let bps: Int
        let receiver: String
    }

    struct EncodingOptions: Encodable, Equatable {
        let slippage: String
        let transferType: String
        let clientFeeParams: ClientFeeParams?

        enum CodingKeys: String, CodingKey {
            case slippage
            case transferType = "transfer_type"
            case clientFeeParams = "client_fee_params"
        }
    }

    struct Options: Encodable, Equatable {
        let timeoutMs: Int
        let minResponses: Int
        let encodingOptions: EncodingOptions

        enum CodingKeys: String, CodingKey {
            case timeoutMs = "timeout_ms"
            case minResponses = "min_responses"
            case encodingOptions = "encoding_options"
        }
    }

    let orders: [Order]
    let options: Options
}

struct FyndQuoteResponse: Decodable {
    let orders: [FyndOrderQuote]
}

struct FyndOrderQuote: Decodable, Equatable {
    struct Transaction: Decodable, Equatable {
        let to: String
        let value: String
        let data: String
        let clientFeeSignatureOffset: Int?

        enum CodingKeys: String, CodingKey {
            case to, value, data
            case clientFeeSignatureOffset = "client_fee_signature_offset"
        }
    }

    struct FeeBreakdown: Decodable, Equatable {
        let routerFee: String
        let clientFee: String
        let maxSlippage: String
        let minAmountReceived: String

        enum CodingKeys: String, CodingKey {
            case routerFee = "router_fee"
            case clientFee = "client_fee"
            case maxSlippage = "max_slippage"
            case minAmountReceived = "min_amount_received"
        }
    }

    let status: String
    let amountIn: String?
    let amountOut: String?
    let gasEstimate: String?
    let gasPrice: String?
    let transaction: Transaction?
    let feeBreakdown: FeeBreakdown?
    /// Unix seconds. Set by the Vultisig proxy when it signs the client fee;
    /// the router reverts a signed quote submitted after it.
    let clientFeeDeadline: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case amountIn = "amount_in"
        case amountOut = "amount_out"
        case gasEstimate = "gas_estimate"
        case gasPrice = "gas_price"
        case transaction
        case feeBreakdown = "fee_breakdown"
        case clientFeeDeadline = "client_fee_deadline"
    }
}

struct FyndErrorResponse: Decodable {
    let error: String
    let code: String
}
