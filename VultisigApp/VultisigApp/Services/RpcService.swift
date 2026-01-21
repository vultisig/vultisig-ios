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

class RpcService {
    
    private let session = URLSession.shared

    internal let rpcEndpoint: String // Modificado para `internal` para permitir acesso pela subclass
    
    init(_ rpcEndpoint: String) {
        self.rpcEndpoint = rpcEndpoint
        guard URL(string: rpcEndpoint) != nil else {
            fatalError("Invalid RPC endpoint URL")
        }
    }
    
    func sendRPCRequest<T>(method: String, params: [Any], decode: (Any) throws -> T) async throws -> T {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]
        
        guard let url = URL(string: rpcEndpoint) else {
            throw RpcServiceError.rpcError(code: 404, message: "We didn't find the URL \(rpcEndpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let responsePreview = String(data: data.prefix(200), encoding: .utf8) ?? "Unable to decode as string"
                throw RpcServiceError.rpcError(code: 500, message: "Error to decode the JSON response. Preview: \(responsePreview)")
            }
            
            if let error = response["error"] as? [String: Any], let message = error["message"] as? String {
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
                
                return try decode(message)
                
            } else if let result = response["result"] {
                return try decode(result)
            } else {
                throw RpcServiceError.rpcError(code: 500, message: "Unknown error")
            }
        } catch {
            print(payload)
            print(error.localizedDescription)
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
            
            print(result)
            
            guard let resultString = result as? String else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to String")
            }
            return resultString
        }
        
    }
}
