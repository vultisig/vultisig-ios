//
//  RpcServiceStruct.swift
//  VultisigApp
//
//  Stateless RPC service - no shared mutable state, so struct is sufficient
//

import Foundation
import BigInt

struct RpcServiceStruct {
    private let url: URL

    init(_ rpcEndpoint: String) throws {
        guard let url = URL(string: rpcEndpoint) else {
            throw RpcServiceError.invalidURL(rpcEndpoint)
        }
        self.url = url
    }

    func sendRPCRequest<T>(method: String, params: [Any], decode: (Any) throws -> T) async throws -> T {
        let response = try await sendRawRPCRequest(method: method, params: params)

        if let error = response["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown RPC error"
            let dataMessage = error["data"] as? String
            let detail = dataMessage.flatMap { $0.isEmpty ? nil : $0 } ?? message

            // Special handling for transaction broadcast errors
            if BroadcastErrorClassifier.broadcastMethods.contains(method),
               BroadcastErrorClassifier.isDuplicateBroadcast(message)
                || BroadcastErrorClassifier.isDuplicateBroadcast(detail) {
                return try decode(SubstrateBroadcast.alreadyBroadcastedSentinel)
            }

            // For other errors, throw an exception instead of trying to decode the error message
            throw RpcServiceError.rpcError(code: code, message: detail)

        } else if let result = response["result"] {
            return try decode(result)
        } else {
            throw RpcServiceError.rpcError(code: 500, message: "Unknown error")
        }
    }

    /// The JSON-RPC response object exactly as the node sent it. An `error`
    /// member is returned, not thrown: `sendRPCRequest` folds `error.data` over
    /// `error.message`, which leaves a caller unable to tell a revert from a
    /// node failure. Only a transport failure or a body that is not a JSON
    /// object throws.
    func sendRawRPCRequest(method: String, params: [Any]) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

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
            throw RpcServiceError.rpcError(code: 500, message: "Error to decode the JSON response")
        }
        return response
    }

    func intRpcCall(method: String, params: [Any]) async throws -> BigInt {
        return try await sendRPCRequest(method: method, params: params) { result in
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

    func strRpcCall(method: String, params: [Any]) async throws -> String {
        return try await sendRPCRequest(method: method, params: params) { result in
            guard let resultString = result as? String else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to String")
            }
            return resultString
        }
    }
}
