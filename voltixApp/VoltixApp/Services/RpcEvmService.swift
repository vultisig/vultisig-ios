import Foundation
import BigInt

enum RpcEvmServiceError: Error {
    case rpcError(code: Int, message: String)
    
    var localizedDescription: String {
        switch self {
        case let .rpcError(code, message):
            return "RPC Error \(code): \(message)"
        }
    }
}

class RpcEvmService {
    
    private let session = URLSession.shared
    internal let rpcEndpoint: String // Modificado para `internal` para permitir acesso pela subclass

    init(_ rpcEndpoint: String) {
        self.rpcEndpoint = rpcEndpoint
        guard URL(string: rpcEndpoint) != nil else {
            fatalError("Invalid RPC endpoint URL")
        }
    }
    
    func getBalance(tx: SendTransaction) async throws -> Void {
        do {
            // Start fetching all information concurrently
            async let cryptoPrice = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"]
            if let priceRateUsd = await cryptoPrice {
                tx.coin.priceRate = priceRateUsd
            }
            if tx.coin.isNativeToken {
                tx.coin.rawBalance = String(try await fetchBalance(address: tx.fromAddress))
            } else {
                tx.coin.rawBalance = String(try await fetchERC20TokenBalance(contractAddress: tx.coin.contractAddress, walletAddress: tx.fromAddress))
                
                print("BALANCE ARC20: \(tx.coin.rawBalance)")
            }
            
        } catch {
            print("getBalance:: \(error.localizedDescription)")
        }
    }
    
    func getGasInfo(fromAddress: String) async throws -> (gasPrice:String,priorityFee:Int64,nonce:Int64){
        async let gasPrice = fetchGasPrice()
        async let nonce = fetchNonce(address: fromAddress)
        async let priorityFee = fetchMaxPriorityFeePerGas()
        return (String(try await gasPrice / BigInt(EVMHelper.weiPerGWei)),Int64(try await priorityFee),Int64(try await nonce))
    }
    
    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        return try await strRpcCall(method: "eth_sendRawTransaction", params: [hexWithPrefix])
    }

    
    func estimateGasForEthTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
        // Convert the memo to hex (if present). Assume memo is a String.
        let memoDataHex = memo?.data(using: .utf8)?.map { byte in String(format: "%02x", byte) }.joined() ?? ""
        
        let transactionObject: [String: Any] = [
            "from": senderAddress,
            "to": recipientAddress,
            "value": "0x" + String(value, radix: 16), // Convert value to hex string
            "data": "0x" + memoDataHex // Include the memo in the data field, if present
        ]
        
        return try await intRpcCall(method: "eth_estimateGas", params: [transactionObject])
    }
    
    func estimateGasForERC20Transfer(senderAddress: String, contractAddress: String, recipientAddress: String, value: BigInt) async throws -> BigInt {
        let data = constructERC20TransferData(recipientAddress: recipientAddress, value: value)
        
        let nonce = try await fetchNonce(address: senderAddress)
        let gasPrice = try await fetchGasPrice()
        
        let transactionObject: [String: Any] = [
            "from": senderAddress,
            "to": contractAddress,
            "value": "0x0",
            "data": data,
            "nonce": "0x\(String(nonce, radix: 16))",
            "gasPrice": "0x\(String(gasPrice, radix: 16))"
        ]
        
        return try await intRpcCall(method: "eth_estimateGas", params: [transactionObject])
    }
    
    func fetchERC20TokenBalance(contractAddress: String, walletAddress: String) async throws -> BigInt {
        // Function signature hash of `balanceOf(address)` is `0x70a08231`
        // The wallet address is stripped of '0x', left-padded with zeros to 64 characters
        let paddedWalletAddress = String(walletAddress.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
        let data = "0x70a08231" + paddedWalletAddress
        
        let params: [Any] = [
            ["to": contractAddress, "data": data],
            "latest"
        ]
        
        return try await intRpcCall(method: "eth_call", params: params)
    }
    
    private func fetchBalance(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "eth_getBalance", params: [address, "latest"])
    }
    
    private func fetchMaxPriorityFeePerGas() async throws -> BigInt {
        return try await intRpcCall(method: "eth_maxPriorityFeePerGas", params: [])
    }
    
    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "eth_getTransactionCount", params: [address, "latest"])
    }
    
    private func fetchGasPrice() async throws -> BigInt {
        return try await intRpcCall(method: "eth_gasPrice", params: [])
    }
    
    private func constructERC20TransferData(recipientAddress: String, value: BigInt) -> String {
        let methodId = "a9059cbb"
        
        // Ensure the recipient address is correctly stripped of the '0x' prefix and then padded
        let strippedRecipientAddress = recipientAddress.stripHexPrefix()
        let paddedAddress = strippedRecipientAddress.paddingLeft(toLength: 64, withPad: "0")
        
        // Convert the BigInt value to a hexadecimal string without leading '0x', then pad
        let valueHex = String(value, radix: 16)
        let paddedValue = valueHex.paddingLeft(toLength: 64, withPad: "0")
        
        // Construct the data string with '0x' prefix
        let data = "0x" + methodId + paddedAddress + paddedValue
        
        return data
    }
    
    func sendRPCRequest<T>(method: String, params: [Any], decode: (Any) throws -> T) async throws -> T {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]
        
        guard let url = URL(string: rpcEndpoint) else {
            throw RpcEvmServiceError.rpcError(code: 404, message: "We didn't find the URL \(rpcEndpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RpcEvmServiceError.rpcError(code: 500, message: "Error to decode the JSON response")
            }
            
            if let error = response["error"] as? [String: Any], let message = error["message"] as? String {
                print("ERROR sendRPCRequest \(message)")
                throw RpcEvmServiceError.rpcError(code: error["code"] as? Int ?? 500, message: message)
            } else if let result = response["result"] {
                return try decode(result)
            } else {
                throw RpcEvmServiceError.rpcError(code: 500, message: "Unknown error")
            }
        } catch {
            print(payload)
            print(error.localizedDescription)
            throw RpcEvmServiceError.rpcError(code: 500, message: error.localizedDescription)
        }

    }
    
    func intRpcCall(method: String, params: [Any]) async throws -> BigInt {
        return try await sendRPCRequest(method: method, params: params) { result in
            guard let resultString = result as? String,
                  let bigIntResult = BigInt(resultString.stripHexPrefix(), radix: 16) else {
                throw RpcEvmServiceError.rpcError(code: 500, message: "Error to convert the RPC result to BigInt")
            }
            return bigIntResult
        }
        
    }
    
    func strRpcCall(method: String, params: [Any]) async throws -> String {
        return try await sendRPCRequest(method: method, params: params) { result in
            guard let resultString = result as? String else {
                throw RpcEvmServiceError.rpcError(code: 500, message: "Error to convert the RPC result to String")
            }
            return resultString
        }
        
    }
}
