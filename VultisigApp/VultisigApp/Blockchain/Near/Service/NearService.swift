//
//  NearService.swift
//  VultisigApp
//

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

    private let client: HTTPClientProtocol

    init(client: HTTPClientProtocol = HTTPClient()) {
        self.client = client
    }

    // MARK: - Reads

    /// `nil` when the node answered UNKNOWN_ACCOUNT, which is a valid answer —
    /// an unfunded account. A transport failure or an unreadable body throws,
    /// so a broken RPC can never read as zero.
    func fetchAccount(accountId: String) async throws -> NearAccountView? {
        let result: NearAccountResult
        do {
            result = try await call(
                method: "query",
                params: [
                    "request_type": "view_account",
                    "finality": "final",
                    "account_id": accountId
                ]
            )
        } catch NearError.unknownAccount {
            return nil
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
        let result: NearAccessKeyResult
        do {
            result = try await call(
                method: "query",
                params: [
                    "request_type": "view_access_key",
                    "finality": "optimistic",
                    "account_id": accountId,
                    "public_key": try Self.publicKeyString(hexPublicKey: hexPublicKey)
                ]
            )
        } catch NearError.unknownAccessKey {
            return nil
        }

        guard result.error == nil, let nonce = result.nonce, let permission = result.permission else {
            return nil
        }

        return NearAccessKeyView(nonce: nonce.value, isFullAccess: permission.isFullAccess)
    }

    /// The final block supplies both frozen signing inputs: its hash and the gas
    /// price the reservation is priced at. A transaction is included in a LATER
    /// block, so the reservation is priced at the current price — it is not a
    /// cap on what the transaction may cost.
    func fetchFinalBlock() async throws -> NearFinalBlockView {
        let method = "block"
        let result: NearBlockResult = try await call(method: method, params: ["finality": "final"])

        guard let header = result.header else {
            throw NearError.malformedResponse("\(method) response is missing its header")
        }
        guard let hash = header.hash else {
            throw NearError.malformedResponse("\(method) response is missing its header hash")
        }
        let width = NearSignedTransaction.blockHashBytes
        guard let decoded = Base58.decodeNoCheck(string: hash), decoded.count == width else {
            throw NearError.malformedResponse("\(method) hash is not \(width) bytes: \(hash)")
        }

        return NearFinalBlockView(hash: decoded, gasPrice: header.gasPrice.value)
    }

    func fetchFeeConfig() async throws -> NearFees.FeeConfig {
        let method = "EXPERIMENTAL_protocol_config"
        let result: NearProtocolConfigResult = try await call(method: method, params: ["finality": "final"])

        guard let runtime = result.runtimeConfig, let costs = runtime.transactionCosts else {
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
        let result: NearTransactionResultBody? = try await optionalCall(
            method: "send_tx",
            params: [
                "signed_tx_base64": signedTransactionBase64,
                "wait_until": "INCLUDED"
            ]
        )
        return result?.outcomeHash
    }

    /// NEAR has no hash-only lookup: the node is asked by
    /// `(tx_hash, sender_account_id)` because the lookup is sharded by sender.
    func fetchTransactionOutcome(hash: String, senderAccountId: String) async throws -> NearTransactionOutcome {
        let result: NearTransactionResultBody = try await call(
            method: "tx",
            params: [
                "tx_hash": hash,
                "sender_account_id": senderAccountId,
                "wait_until": "FINAL"
            ]
        )

        return NearTransactionOutcome(
            returnedHash: result.outcomeHash,
            finalExecutionStatus: result.finalExecutionStatus,
            status: result.status
        )
    }

    // MARK: - Transport

    private static func publicKeyString(hexPublicKey: String) throws -> String {
        guard let key = Data(hexString: hexPublicKey), key.count == NearSignedTransaction.ed25519PublicKeyBytes else {
            throw NearError.invalidInput("\(hexPublicKey) is not a 32-byte Ed25519 public key")
        }
        return "ed25519:\(Base58.encodeNoCheck(data: key))"
    }

    private static func parameterCost(_ value: NearParameterCostBody?, label: String) throws -> NearFees.ParameterCost {
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

    /// The method's `result`. A JSON-RPC error throws as its typed `NearError`,
    /// and so does a body carrying neither.
    private func call<Result: Decodable>(method: String, params: [String: Any]) async throws -> Result {
        guard let result: Result = try await optionalCall(method: method, params: params) else {
            throw NearError.malformedResponse("\(method) returned neither a result nor an error")
        }
        return result
    }

    /// `call` for `send_tx`, which may acknowledge without a result.
    private func optionalCall<Result: Decodable>(method: String, params: [String: Any]) async throws -> Result? {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": method,
            "method": method,
            "params": params
        ])

        let response = try await client.request(NearAPI(baseURL: Self.endpoint, body: body))

        let envelope: NearRPCEnvelope<Result>
        do {
            envelope = try JSONDecoder().decode(NearRPCEnvelope<Result>.self, from: response.data)
        } catch {
            throw NearError.malformedResponse("\(method) response could not be read: \(error)")
        }
        if let error = envelope.resolvedError(method: method) {
            throw error
        }
        return envelope.result
    }
}
