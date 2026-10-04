//
//  NearService.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

/// NEAR JSON-RPC (mainnet). Everything the native transfer path freezes at
/// preparation time comes from here: the access-key nonce, the final block's
/// hash and gas price, and the runtime config the gas reservation is priced
/// from.
///
/// The node is the SDK's mainnet endpoint, so a payload prepared here and one
/// prepared by the extension/SDK resolve the same block and the same config.
final class NearService {

    static let rpcEndpoint = Endpoint.nearServiceRpc
    static let shared = NearService()

    private static let blockHashBytes = 32

    private let client: HTTPClientProtocol

    init(client: HTTPClientProtocol = HTTPClient()) {
        self.client = client
    }

    // MARK: - Reads

    /// `nil` when the node answered UNKNOWN_ACCOUNT, which is a valid answer —
    /// an unfunded account. A transport failure or an unreadable body throws,
    /// so a broken RPC can never read as zero.
    func fetchAccount(accountId: String) async throws -> NearAccountView? {
        let method = "query"
        let envelope: NearRPCEnvelope<AccountResult> = try await call(
            method: method,
            params: [
                "request_type": "view_account",
                "finality": "final",
                "account_id": accountId
            ]
        )

        if let error = envelope.resolvedError(method: method) {
            if case .unknownAccount = error {
                return nil
            }
            throw error
        }

        guard let result = envelope.result else {
            throw NearError.malformedResponse("\(method) returned neither a result nor an error")
        }

        return NearAccountView(
            amount: result.amount.value,
            locked: result.locked.value,
            storageUsage: result.storageUsage.value
        )
    }

    /// `nil` when the account does not hold this key. The node reports a
    /// missing key as a `result.error` string rather than as a JSON-RPC error,
    /// so the answer is read rather than thrown.
    ///
    /// Read at `optimistic` finality: the nonce is the latest one, so a second
    /// send inside the finality window does not reuse it (`InvalidNonce`).
    func fetchAccessKey(accountId: String, hexPublicKey: String) async throws -> NearAccessKeyView? {
        let method = "query"
        let envelope: NearRPCEnvelope<AccessKeyResult> = try await call(
            method: method,
            params: [
                "request_type": "view_access_key",
                "finality": "optimistic",
                "account_id": accountId,
                "public_key": try Self.publicKeyString(hexPublicKey: hexPublicKey)
            ]
        )

        if let error = envelope.resolvedError(method: method) {
            if case .unknownAccessKey = error {
                return nil
            }
            throw error
        }

        guard let result = envelope.result else {
            throw NearError.malformedResponse("\(method) returned neither a result nor an error")
        }
        guard result.error == nil, let nonce = result.nonce, let permission = result.permission else {
            return nil
        }

        return NearAccessKeyView(nonce: nonce.value, isFullAccess: permission == "FullAccess")
    }

    /// The final block supplies both frozen signing inputs: its hash and the gas
    /// price the reservation is priced at. A transaction is included in a LATER
    /// block, so the reservation is priced at the current price — it is not a
    /// cap on what the transaction may cost.
    func fetchFinalBlock() async throws -> NearFinalBlockView {
        let method = "block"
        let envelope: NearRPCEnvelope<BlockResult> = try await call(method: method, params: ["finality": "final"])

        if let error = envelope.resolvedError(method: method) {
            throw error
        }

        guard let header = envelope.result?.header else {
            throw NearError.malformedResponse("\(method) response is missing its header")
        }
        guard let hash = header.hash else {
            throw NearError.malformedResponse("\(method) response is missing its header hash")
        }
        guard let decoded = Base58.decodeNoCheck(string: hash), decoded.count == Self.blockHashBytes else {
            throw NearError.malformedResponse("\(method) hash is not \(Self.blockHashBytes) bytes: \(hash)")
        }

        return NearFinalBlockView(hash: decoded, gasPrice: header.gasPrice.value)
    }

    func fetchFeeConfig() async throws -> NearFees.FeeConfig {
        let method = "EXPERIMENTAL_protocol_config"
        let envelope: NearRPCEnvelope<ProtocolConfigResult> = try await call(
            method: method,
            params: ["finality": "final"]
        )

        if let error = envelope.resolvedError(method: method) {
            throw error
        }

        guard let runtime = envelope.result?.runtimeConfig, let costs = runtime.transactionCosts else {
            throw NearError.malformedResponse("\(method) response is missing its runtime_config")
        }

        return NearFees.FeeConfig(
            actionReceiptCreation: try Self.parameterCost(costs.actionReceiptCreation, label: "receipt creation"),
            transfer: try Self.parameterCost(costs.actionCreation?.transfer, label: "transfer"),
            createAccount: try Self.parameterCost(costs.actionCreation?.createAccount, label: "create account"),
            addFullAccessKey: try Self.parameterCost(
                costs.actionCreation?.addKey?.fullAccess,
                label: "add full access key"
            ),
            minGasPurchasePrice: runtime.minGasPurchasePrice.value,
            storageAmountPerByte: runtime.storageAmountPerByte.value
        )
    }

    // MARK: - Broadcast and status

    /// Submits the frozen signed bytes and returns the hash the node reports,
    /// when it reports one. The caller binds that answer to the hash derived
    /// locally from the same bytes, so an acknowledgement for another
    /// transaction cannot be read as this one.
    func sendTransaction(signedTransactionBase64: String) async throws -> String? {
        let method = "send_tx"
        let envelope: NearRPCEnvelope<TransactionResultBody> = try await call(
            method: method,
            params: [
                "signed_tx_base64": signedTransactionBase64,
                "wait_until": "INCLUDED"
            ]
        )

        if let error = envelope.resolvedError(method: method) {
            throw error
        }

        return envelope.result?.outcomeHash
    }

    /// NEAR has no hash-only lookup: the node is asked by
    /// `(tx_hash, sender_account_id)` because the lookup is sharded by sender.
    func fetchTransactionOutcome(hash: String, senderAccountId: String) async throws -> NearTransactionOutcome {
        let method = "tx"
        let envelope: NearRPCEnvelope<TransactionResultBody> = try await call(
            method: method,
            params: [
                "tx_hash": hash,
                "sender_account_id": senderAccountId,
                "wait_until": "FINAL"
            ]
        )

        if let error = envelope.resolvedError(method: method) {
            throw error
        }

        guard let result = envelope.result else {
            throw NearError.malformedResponse("\(method) returned neither a result nor an error")
        }

        return NearTransactionOutcome(
            returnedHash: result.outcomeHash,
            finalExecutionStatus: result.finalExecutionStatus,
            status: result.status
        )
    }

    // MARK: - Transport

    private static func publicKeyString(hexPublicKey: String) throws -> String {
        guard let key = Data(hexString: hexPublicKey), key.count == 32 else {
            throw NearError.malformedResponse("\(hexPublicKey) is not a 32-byte Ed25519 public key")
        }
        return "ed25519:\(Base58.encodeNoCheck(data: key))"
    }

    private static func parameterCost(_ value: ParameterCostBody?, label: String) throws -> NearFees.ParameterCost {
        guard let value else {
            throw NearError.malformedResponse("runtime config is missing transaction_costs.\(label)")
        }
        return NearFees.ParameterCost(
            sendSir: value.sendSir.value,
            sendNotSir: value.sendNotSir.value,
            execution: value.execution.value
        )
    }

    private static let endpoint: URL = {
        guard let url = URL(string: rpcEndpoint) else {
            preconditionFailure("Invalid NEAR RPC endpoint URL: \(rpcEndpoint)")
        }
        return url
    }()

    private func call<Result: Decodable>(
        method: String,
        params: [String: Any]
    ) async throws -> NearRPCEnvelope<Result> {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": method,
            "method": method,
            "params": params
        ])

        let response = try await client.request(NearRPCRequest(baseURL: Self.endpoint, body: body))

        do {
            return try JSONDecoder().decode(NearRPCEnvelope<Result>.self, from: response.data)
        } catch {
            throw NearError.malformedResponse("\(method) response could not be read: \(error)")
        }
    }
}

// MARK: - Transport target

private struct NearRPCRequest: TargetType {
    let baseURL: URL
    let body: Data

    var path: String { "" }
    var method: HTTPMethod { .post }
    var task: HTTPTask { .requestData(body) }
}

// MARK: - Wire models

/// Exact non-negative integer from a JSON field that may arrive as a number or
/// as a string. The cast to `Int64` is deliberate: it fails on a fractional or
/// out-of-range number rather than rounding it, and an access-key nonce above
/// 2^53 is exactly the value a `Double` would corrupt.
struct NearExactInteger: Decodable {
    let value: BigInt

    private static let unsignedDecimal = "^[0-9]+$"

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
        guard text.range(of: Self.unsignedDecimal, options: .regularExpression) != nil,
              let parsed = BigInt(text) else {
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

private struct AccountResult: Decodable {
    let amount: NearExactInteger
    let locked: NearExactInteger
    let storageUsage: NearExactInteger

    private enum CodingKeys: String, CodingKey {
        case amount
        case locked
        case storageUsage = "storage_usage"
    }
}

private struct AccessKeyResult: Decodable {
    let error: String?
    let nonce: NearExactInteger?
    let permission: String?
}

private struct BlockResult: Decodable {
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

private struct ProtocolConfigResult: Decodable {
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
        let actionReceiptCreation: ParameterCostBody?

        private enum CodingKeys: String, CodingKey {
            case actionCreation = "action_creation_config"
            case actionReceiptCreation = "action_receipt_creation_config"
        }
    }

    struct ActionCreation: Decodable {
        let transfer: ParameterCostBody?
        let createAccount: ParameterCostBody?
        let addKey: AddKey?

        private enum CodingKeys: String, CodingKey {
            case transfer = "transfer_cost"
            case createAccount = "create_account_cost"
            case addKey = "add_key_cost"
        }

        struct AddKey: Decodable {
            let fullAccess: ParameterCostBody?

            private enum CodingKeys: String, CodingKey {
                case fullAccess = "full_access_cost"
            }
        }
    }
}

private struct ParameterCostBody: Decodable {
    let sendSir: NearExactInteger
    let sendNotSir: NearExactInteger
    let execution: NearExactInteger

    private enum CodingKeys: String, CodingKey {
        case sendSir = "send_sir"
        case sendNotSir = "send_not_sir"
        case execution
    }
}

private struct TransactionResultBody: Decodable {
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
