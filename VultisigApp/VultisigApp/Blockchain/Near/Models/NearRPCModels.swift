//
//  NearRPCModels.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Exact non-negative integer from a JSON field that may arrive as a number or
/// as a string. The cast to `Int64` is deliberate: it fails on a fractional or
/// out-of-range number rather than rounding it, and an access-key nonce above
/// 2^53 is exactly the value a `Double` would corrupt.
struct NearExactInteger: Decodable {
    let value: BigInt

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Int64.self) {
            guard number >= 0 else {
                throw NearError.malformedResponse("expected a non-negative integer, read \(number)")
            }
            value = BigInt(number)
            return
        }

        let text = try container.decode(String.self)
        guard text.isUnsignedDecimal, let parsed = BigInt(text) else {
            throw NearError.malformedResponse("expected an unsigned decimal integer, read \(text)")
        }
        value = parsed
    }
}

struct NearRPCEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: NearRPCErrorBody?

    /// `nil` for a successful body; the typed NEAR error otherwise.
    func resolvedError(method: String) -> NearError? {
        error?.nearError(method: method)
    }
}

struct NearRPCErrorBody: Decodable {
    let name: String?
    let message: String?
    let data: String?
    let cause: Cause?

    struct Cause: Decodable {
        let name: String?
    }

    /// `name` is read from the handler's nested `cause` when the endpoint puts
    /// it there (`query` nests one level deeper than `tx` does), because the
    /// name is the only part that distinguishes a missing record from a
    /// timeout from a rejection.
    func nearError(method: String) -> NearError {
        let resolvedName = cause?.name ?? name ?? "UNKNOWN_ERROR"
        let detail = data.flatMap { $0.isEmpty ? nil : $0 } ?? message ?? "unknown error"
        return NearError.unknownEntity(forRPCName: resolvedName, detail: detail)
            ?? .rpc(method: method, name: resolvedName, message: detail)
    }
}

struct NearAccountView {
    let amount: BigInt
    let locked: BigInt
    let storageUsage: BigInt
}

struct NearAccessKeyView {
    let nonce: BigInt
    let isFullAccess: Bool
}

struct NearFinalBlockView {
    /// The 32-byte block hash the transaction is anchored to.
    let hash: Data
    let gasPrice: BigInt
}

/// What the node knows about a transaction, before finality is interpreted.
struct NearTransactionOutcome {
    let returnedHash: String?
    let finalExecutionStatus: String?
    let status: NearExecutionStatus?
}

/// `tx` / `send_tx` render an outcome either as a bare string (`"SuccessValue"`)
/// or as a single-key object (`{"SuccessValue": ""}`, `{"Failure": {…}}`).
enum NearExecutionStatus: Decodable {
    case success
    case failure
    case unrecognized(String)

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let name = try? single.decode(String.self) {
            self = Self.named(name)
            return
        }

        let object = try decoder.container(keyedBy: NearDynamicKey.self)
        guard let key = object.allKeys.first else {
            throw NearError.malformedResponse("execution status object is empty")
        }
        self = Self.named(key.stringValue)
    }

    private static func named(_ name: String) -> NearExecutionStatus {
        switch name {
        case "SuccessValue", "SuccessReceiptId":
            return .success
        case "Failure":
            return .failure
        default:
            return .unrecognized(name)
        }
    }
}

struct NearDynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Endpoint result shapes

struct NearAccountResult: Decodable {
    let amount: NearExactInteger
    let locked: NearExactInteger
    let storageUsage: NearExactInteger

    private enum CodingKeys: String, CodingKey {
        case amount
        case locked
        case storageUsage = "storage_usage"
    }
}

struct NearAccessKeyResult: Decodable {
    let error: String?
    let nonce: NearExactInteger?
    let permission: Permission?

    /// The string `"FullAccess"`, or an object such as `{"FunctionCall": {…}}`
    /// for a key restricted to contract calls.
    struct Permission: Decodable {
        let isFullAccess: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            isFullAccess = (try? container.decode(String.self)) == "FullAccess"
        }
    }
}

struct NearBlockResult: Decodable {
    let header: Header?

    struct Header: Decodable {
        let hash: String?
        let gasPrice: NearExactInteger

        private enum CodingKeys: String, CodingKey {
            case hash
            case gasPrice = "gas_price"
        }
    }
}

struct NearProtocolConfigResult: Decodable {
    let runtimeConfig: RuntimeConfig?

    private enum CodingKeys: String, CodingKey {
        case runtimeConfig = "runtime_config"
    }

    struct RuntimeConfig: Decodable {
        let minGasPurchasePrice: NearExactInteger
        let storageAmountPerByte: NearExactInteger
        let transactionCosts: TransactionCosts?

        private enum CodingKeys: String, CodingKey {
            case minGasPurchasePrice = "min_gas_purchase_price"
            case storageAmountPerByte = "storage_amount_per_byte"
            case transactionCosts = "transaction_costs"
        }
    }

    struct TransactionCosts: Decodable {
        let actionCreation: ActionCreation?
        let actionReceiptCreation: NearParameterCostBody?

        private enum CodingKeys: String, CodingKey {
            case actionCreation = "action_creation_config"
            case actionReceiptCreation = "action_receipt_creation_config"
        }
    }

    struct ActionCreation: Decodable {
        let transfer: NearParameterCostBody?
        let createAccount: NearParameterCostBody?
        let addKey: AddKey?

        private enum CodingKeys: String, CodingKey {
            case transfer = "transfer_cost"
            case createAccount = "create_account_cost"
            case addKey = "add_key_cost"
        }

        struct AddKey: Decodable {
            let fullAccess: NearParameterCostBody?

            private enum CodingKeys: String, CodingKey {
                case fullAccess = "full_access_cost"
            }
        }
    }
}

struct NearParameterCostBody: Decodable {
    let sendSir: NearExactInteger
    let sendNotSir: NearExactInteger
    let execution: NearExactInteger

    private enum CodingKeys: String, CodingKey {
        case sendSir = "send_sir"
        case sendNotSir = "send_not_sir"
        case execution
    }
}

struct NearTransactionResultBody: Decodable {
    let finalExecutionStatus: String?
    let status: NearExecutionStatus?
    let transaction: Transaction?
    let outcome: Outcome?

    private enum CodingKeys: String, CodingKey {
        case finalExecutionStatus = "final_execution_status"
        case status
        case transaction
        case outcome = "transaction_outcome"
    }

    struct Transaction: Decodable {
        let hash: String?
    }

    struct Outcome: Decodable {
        let id: String?
    }

    var outcomeHash: String? {
        let hash = transaction?.hash ?? outcome?.id
        return hash.flatMap { $0.isEmpty ? nil : $0 }
    }
}
