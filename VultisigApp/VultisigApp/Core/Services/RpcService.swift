import Foundation
import BigInt

enum RpcServiceError: LocalizedError {
    case rpcError(code: Int, message: String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .rpcError(code, message):
            return "RPC Error \(code): \(message)"
        case let .invalidURL(url):
            return "Invalid RPC endpoint URL: \(url)"
        }
    }
}

/// Validation for substrate `author_submitExtrinsic` broadcast results.
///
/// `RpcService.sendRPCRequest` returns a sentinel for duplicate broadcasts so
/// callers can recover the locally computed transaction hash. Polkadot and
/// Bittensor route successful results through this validator to ensure only a
/// real extrinsic hash or that sentinel is persisted and polled as a txid.
enum SubstrateBroadcast {
    /// Sentinel `RpcService.sendRPCRequest` returns when an extrinsic is
    /// rejected as a duplicate (already known / already imported). Callers
    /// downstream map it to the locally computed extrinsic hash.
    static let alreadyBroadcastedSentinel = "Transaction already broadcasted."

    /// Returns `result` when it is an accepted broadcast — the 32-byte extrinsic
    /// hash (`0x` + 64 hex) or the duplicate sentinel — otherwise throws.
    static func validatedHash(_ result: String) throws -> String {
        if result == alreadyBroadcastedSentinel {
            return result
        }
        let hash = result.stripHexPrefix()
        if hash.count == 64, hash.allSatisfy(\.isHexDigit) {
            return result
        }
        throw RpcServiceError.rpcError(code: 500, message: "Broadcast rejected: \(result)")
    }
}

/// Classifies a JSON-RPC broadcast error message or detail as a *true*
/// duplicate — the signed tx is already in the mempool or on-chain — versus a
/// genuine rejection.
///
/// Only exact duplicate signals count. Substrings that used to match here caused
/// rejections to be reported as success: `"known"` matched every `"unknown …"`
/// message, `"nonce too high"` is a nonce gap (tx NOT accepted), the rate-limit
/// message means the tx may never have been submitted, and a bare `"already"`
/// matched almost anything. Those are excluded on purpose.
enum BroadcastErrorClassifier {
    /// RPC methods that submit a signed transaction. Only these may recover a
    /// duplicate error as success — a duplicate-looking error from a read call
    /// (e.g. `state_getStorage`) must throw, not return the sentinel.
    static let broadcastMethods: Set<String> = ["author_submitExtrinsic", "eth_sendRawTransaction"]

    static func isDuplicateBroadcast(_ message: String) -> Bool {
        let message = message.lowercased()
        return message.contains("already known")
            || message.contains("already exists")
            || message.contains("already_exists")
            || message.contains("already imported")
            || message.contains("already mined")
            || message.contains("transaction is temporarily banned")
            || message.contains("nonce too low")
    }
}

class RpcService {
    internal let rpcEndpoint: String // Modificado para `internal` para permitir acesso pela subclass

    init(_ rpcEndpoint: String) {
        self.rpcEndpoint = rpcEndpoint
        guard URL(string: rpcEndpoint) != nil else {
            fatalError("Invalid RPC endpoint URL")
        }
    }

    /// Sends a JSON-RPC request. `endpoint` defaults to this service's baked-in
    /// `rpcEndpoint` so existing callers are unchanged; subclasses that resolve a
    /// custom RPC override (e.g. Polkadot / Bittensor) pass the resolved host.
    func sendRPCRequest<T>(
        method: String,
        params: [Any],
        endpoint: String? = nil,
        decode: (Any) throws -> T
    ) async throws -> T {
        let endpoint = endpoint ?? rpcEndpoint
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        guard let url = URL(string: endpoint) else {
            throw RpcServiceError.rpcError(code: 404, message: "We didn't find the URL \(endpoint)")
        }

        // Generic JSON-RPC client used across many chains; doesn't fit
        // `TargetType`/`HTTPClient`'s typed-JSON model.
        // swiftlint:disable:next no_raw_urlrequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        // swiftlint:disable:next no_raw_urlsession
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let responsePreview = String(data: data.prefix(200), encoding: .utf8) ?? "Unable to decode as string"
            throw RpcServiceError.rpcError(code: 500, message: "Error to decode the JSON response. Preview: \(responsePreview)")
        }

        if let error = response["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown RPC error"
            let dataMessage = error["data"] as? String
            let detail = dataMessage.flatMap { $0.isEmpty ? nil : $0 } ?? message

            if BroadcastErrorClassifier.broadcastMethods.contains(method),
               BroadcastErrorClassifier.isDuplicateBroadcast(message)
                || BroadcastErrorClassifier.isDuplicateBroadcast(detail) {
                return try decode(SubstrateBroadcast.alreadyBroadcastedSentinel)
            }

            throw RpcServiceError.rpcError(code: code, message: detail)
        } else if let result = response["result"] {
            return try decode(result)
        } else {
            throw RpcServiceError.rpcError(code: 500, message: "Unknown error")
        }
    }

    func intRpcCall(method: String, params: [Any], endpoint: String? = nil) async throws -> BigInt {
        return try await sendRPCRequest(method: method, params: params, endpoint: endpoint) { result in

            if let intValue = result as? Int64 {
                return BigInt(intValue)
            }

            if let resultString = result as? String,
               let bigIntResult = BigInt(resultString.stripHexPrefix(), radix: 16) {
                return bigIntResult
            }

            throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to BigInt")
        }
    }

    func strRpcCall(method: String, params: [Any], endpoint: String? = nil) async throws -> String {
        return try await sendRPCRequest(method: method, params: params, endpoint: endpoint) { result in
            guard let resultString = result as? String else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to String")
            }
            return resultString
        }

    }
}
