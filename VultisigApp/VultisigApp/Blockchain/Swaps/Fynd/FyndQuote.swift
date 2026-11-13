//
//  FyndQuote.swift
//  VultisigApp
//
//  Wire models for Propeller Heads' Fynd quote API (`POST /v1/{chain}/quote`).
//  Field names follow the Fynd OpenAPI schema (snake_case).
//

import BigInt
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

/// The arguments of a TychoRouterV3 `transfer_from` swap call, decoded from
/// calldata. Only `splitSwap`, `sequentialSwap` and `singleSwap` are accepted:
/// the vault and Permit2 entrypoints are never requested.
struct FyndRouterCall: Equatable {
    let amountIn: BigInt
    let tokenIn: String
    let tokenOut: String
    let expectedAmountOut: BigInt
    let minAmountOut: BigInt
    let receiver: String
    /// Router fee units: 100,000,000 = 100%, so 1 bps = 10,000.
    let clientFeeUnits: BigInt
    let clientFeeReceiver: String
    let maxClientContribution: BigInt
    let clientFeeDeadline: BigInt
    let clientSignature: String

    static let splitSwapSelector = "fe745a0f"
    static let sequentialSwapSelector = "3c226834"
    static let singleSwapSelector = "0c1a0ee7"

    /// `calldata` is lowercase hex without `0x`.
    static func decode(_ calldata: String) -> FyndRouterCall? {
        let hex = Array(calldata)
        guard hex.count >= 8 else { return nil }
        let selector = String(hex[0..<8])
        // splitSwap carries an extra `nTokens` word before `receiver`.
        let receiverIndex: Int
        switch selector {
        case splitSwapSelector: receiverIndex = 6
        case sequentialSwapSelector, singleSwapSelector: receiverIndex = 5
        default: return nil
        }
        let args = Array(hex[8...])

        func word(_ base: Int, _ index: Int) -> BigInt? {
            let start = base + index * 64
            guard start >= 0, start + 64 <= args.count else { return nil }
            return BigInt(String(args[start..<(start + 64)]), radix: 16)
        }
        func address(_ base: Int, _ index: Int) -> String? {
            guard let value = word(base, index), value >= 0, value < (BigInt(1) << 160) else { return nil }
            let hex = String(value, radix: 16)
            return "0x" + String(repeating: "0", count: 40 - hex.count) + hex
        }
        func offset(_ base: Int, _ index: Int) -> Int? {
            guard let value = word(base, index), value >= 0, value < BigInt(args.count) else { return nil }
            return Int(value) * 2
        }

        guard let amountIn = word(0, 0),
              let tokenIn = address(0, 1),
              let tokenOut = address(0, 2),
              let expected = word(0, 3),
              let minOut = word(0, 4),
              let receiver = address(0, receiverIndex),
              let feeTuple = offset(0, receiverIndex + 1),
              let feeUnits = word(feeTuple, 0),
              let feeReceiver = address(feeTuple, 1),
              let maxContribution = word(feeTuple, 2),
              let deadline = word(feeTuple, 3),
              let signatureOffset = offset(feeTuple, 4),
              let signatureLength = word(feeTuple + signatureOffset, 0),
              signatureLength <= BigInt(args.count) else {
            return nil
        }
        let signatureStart = feeTuple + signatureOffset + 64
        let signatureEnd = signatureStart + Int(signatureLength) * 2
        guard signatureEnd <= args.count else { return nil }

        return FyndRouterCall(
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            expectedAmountOut: expected,
            minAmountOut: minOut,
            receiver: receiver,
            clientFeeUnits: feeUnits,
            clientFeeReceiver: feeReceiver,
            maxClientContribution: maxContribution,
            clientFeeDeadline: deadline,
            clientSignature: String(args[signatureStart..<signatureEnd])
        )
    }
}
