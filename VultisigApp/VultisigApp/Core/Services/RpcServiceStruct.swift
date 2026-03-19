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
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to decode the JSON response")
            }

            if let error = response["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -1
                let message = error["message"] as? String ?? "Unknown RPC error"

                // Special handling for transaction broadcast errors
                if message.lowercased().contains("known".lowercased())
                    || message.lowercased().contains("already known".lowercased())
                    || message.lowercased().contains("Transaction is temporarily banned".lowercased())
                    || message.lowercased().contains("nonce too low".lowercased())
                    || message.lowercased().contains("nonce too high".lowercased())
                    || message.lowercased().contains("transaction already exists".lowercased())
                    || message.lowercased().contains("many requests for a specific RPC call".lowercased())
                    || message.lowercased().contains("already".lowercased())
                    || message.lowercased().contains("already mined".lowercased()) {
                    return try decode("Transaction already broadcasted.")
                }

                // For other errors, throw an exception instead of trying to decode the error message
                throw RpcServiceError.rpcError(code: code, message: message)

            } else if let result = response["result"] {
                return try decode(result)
            } else {
                throw RpcServiceError.rpcError(code: 500, message: "Unknown error")
            }
        } catch {
            throw error
        }
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
