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

class RpcEvmService: RpcService {
    
    private let oneInchService = OneInchService.shared

    func getBalance(coin: Coin) async throws -> String {
        if coin.isNativeToken {
            let balance = try await fetchBalance(address: coin.address)
            return String(balance)
        } else {
            let balance = try await fetchERC20TokenBalance(
                contractAddress: coin.contractAddress,
                walletAddress: coin.address
            )
            return String(balance)
        }
    }
    
    func getGasInfo(fromAddress: String, mode: FeeMode) async throws -> (gasPrice: BigInt, priorityFee: BigInt, nonce: Int64) {
        async let gasPrice = fetchGasPrice()
        async let nonce = fetchNonce(address: fromAddress)
        async let priorityFeeMap = fetchMaxPriorityFeesPerGas()

        let gasPriceValue = try await gasPrice
        let priorityFeeMapValue = try await priorityFeeMap
        let nonceValue = try await nonce

        let priorityFee = priorityFeeMapValue[mode] ?? .zero

        return (gasPriceValue, priorityFee, Int64(nonceValue))
    }

    func fetchMaxPriorityFeesPerGas() async throws -> [FeeMode: BigInt] {
        let history = try await getFeeHistory()

        func priorityFeesMap(low: BigInt, normal: BigInt, fast: BigInt) -> [FeeMode: BigInt] {
            return [.safeLow: low, .normal: normal, .fast: fast]
        }

        guard history.count > 0 else {
            let value = try await fetchMaxPriorityFeePerGas()
            return priorityFeesMap(low: value, normal: value, fast: value)
        }

        let low = history[0]
        let normal = history[history.count / 2]
        let fast = history[history.count - 1]

        return priorityFeesMap(low: low, normal: normal, fast: fast)
    }

    func getFeeHistory() async throws -> [BigInt] {
        return try await sendRPCRequest(method: "eth_feeHistory", params: [10, "latest", [5]]) { result in
            guard
                let result = result as? [String: Any],
                let rewards = result["reward"] as? [[String]] else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid response from eth_feeHistory")
            }

            let reward = rewards
                .compactMap { $0.first }
                .compactMap { BigInt($0.stripHexPrefix(), radix: 16) }
                .sorted()

            return reward
        }
    }


    func getBaseFee() async throws -> BigInt {
        return try await sendRPCRequest(method: "eth_getBlockByNumber", params: ["latest", true]) { result in
            guard
                let result = result as? [String: Any],
                let baseFeeString = result["baseFeePerGas"] as? String,
                let baseFee = BigInt(baseFeeString.stripHexPrefix(), radix: 16) else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid response from eth_getBlockByNumber")
            }

            return baseFee
        }
    }

    func getGasInfoZk(fromAddress: String, toAddress: String, memo: String = "0xffffffff") async throws -> (gasLimit: BigInt, gasPerPubdataLimit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt, nonce: Int64) {
        let memoDataHex = memo.data(using: .utf8)?.map { byte in String(format: "%02x", byte) }.joined() ?? ""
        let data = "0x" + memoDataHex
        
        async let nonce = fetchNonce(address: fromAddress)
        async let feeEstimate = zksEstimateFee(fromAddress: fromAddress, toAddress: toAddress, data: data)
        
        let feeEstimateValue = try await feeEstimate
        
        return (feeEstimateValue.gasLimit, feeEstimateValue.gasPerPubdataLimit, feeEstimateValue.maxFeePerGas, feeEstimateValue.maxPriorityFeePerGas, Int64(try await nonce))
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
    
    func fetchAllowance(contractAddress: String, owner: String, spender: String) async throws -> BigInt {
        let paddedOwner = String(owner.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
        let paddedSpender = String(spender.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
        
        let data = "0xdd62ed3e" + paddedOwner + paddedSpender
        let params: [Any] = [["to": contractAddress, "data": data], "latest"]
        
        return try await intRpcCall(method: "eth_call", params: params)
    }

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        do {
            // Define ABI for ERC20 functions
            let erc20Abi = [
                "0x06fdde03", // name()
                "0x95d89b41", // symbol()
                "0x313ce567"  // decimals()
            ]
            
            // Fetch token details in parallel
            async let nameHex = fetchERC20Data(methodId: erc20Abi[0], contractAddress: contractAddress)
            async let symbolHex = fetchERC20Data(methodId: erc20Abi[1], contractAddress: contractAddress)
            async let decimalsHex = fetchERC20Data(methodId: erc20Abi[2], contractAddress: contractAddress)
            
            // Await results
            let nameData = try await nameHex
            let symbolData = try await symbolHex
            let decimalsData = try await decimalsHex
            
            // Decode hex values to respective types
            let name = try decodeAbiString(from: nameData)
            let symbol = try decodeAbiString(from: symbolData)
            let decimals = Int(hex: decimalsData) ?? 0
            
            return (name, symbol, decimals)
        } catch {
            print(error.localizedDescription)
            return (.empty, .empty, .zero)
        }
    }
    
    private func fetchERC20Data(methodId: String, contractAddress: String) async throws -> String {
        let params: [Any] = [
            ["to": contractAddress, "data": methodId],
            "latest"
        ]
        return try await strRpcCall(method: "eth_call", params: params)
    }
    
    private func decodeAbiString(from hex: String) throws -> String {
        let cleanedHex = hex.stripHexPrefix()
        guard let data = Data(hexString: cleanedHex) else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid hex string")
        }
        
        // ABI-encoded strings are padded to 32-byte words. The actual string length is stored at the beginning.
        guard data.count >= 64 else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid ABI-encoded string")
        }
        
        let lengthData = data[32..<64]
        let length = Int(BigUInt(lengthData))
        
        guard length > 0 && data.count >= 64 + length else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid ABI-encoded string length")
        }
        
        let stringData = data[64..<(64 + length)]
        return String(data: stringData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
    }
    
    private func fetchBalance(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "eth_getBalance", params: [address, "latest"])
    }
    
    func fetchMaxPriorityFeePerGas() async throws -> BigInt {
        return try await intRpcCall(method: "eth_maxPriorityFeePerGas", params: []) //WEI
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
    
    private func zksEstimateFee(fromAddress: String, toAddress: String, data: String) async throws -> (gasLimit: BigInt, gasPerPubdataLimit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt) {
        return try await sendRPCRequest(method: "zks_estimateFee", params: [["from": fromAddress, "to": toAddress, "data": data]]) { result in
            guard let response = result as? [String: Any],
                  let gasLimitHex = response["gas_limit"] as? String,
                  let gasPerPubdataLimitHex = response["gas_per_pubdata_limit"] as? String,
                  let maxFeePerGasHex = response["max_fee_per_gas"] as? String,
                  let maxPriorityFeePerGasHex = response["max_priority_fee_per_gas"] as? String
            else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid response from zks_estimateFee")
            }
            
            let gasLimit = BigInt(gasLimitHex.stripHexPrefix(), radix: 16) ?? BigInt(0)
            let gasPerPubdataLimit = BigInt(gasPerPubdataLimitHex.stripHexPrefix(), radix: 16) ?? BigInt(0)
            let maxFeePerGas = BigInt(maxFeePerGasHex.stripHexPrefix(), radix: 16) ?? BigInt(0)
            let maxPriorityFeePerGas = BigInt(maxPriorityFeePerGasHex.stripHexPrefix(), radix: 16) ?? BigInt(0)
            
            return (gasLimit, gasPerPubdataLimit, maxFeePerGas, maxPriorityFeePerGas)
        }
    }
    
    func getTokens(nativeToken: Coin) async -> [CoinMeta] {
        do {
            // First RPC call to get token balances
            let tokenBalances = try await sendRPCRequest(
                method: "alchemy_getTokenBalances",
                params: [nativeToken.address]
            ) { result in
                guard
                    let response = result as? [String: Any],
                    let _ = response["address"] as? String,
                    let tokenBalances = response["tokenBalances"] as? [[String: Any]]
                else {
                    throw RpcServiceError.rpcError(code: -1, message: "Invalid JSON for alchemy_getTokenBalances")
                }
                
                return tokenBalances
            }
            
            // Now we have our token balances array synchronously.
            var tokenMetadata: [CoinMeta] = []
            
            // For each token, we need to fetch metadata
            for tokenBalance in tokenBalances {
                guard
                    let contractAddress = tokenBalance["contractAddress"] as? String
                else {
                    // Skip invalid entries if needed
                    continue
                }
                
                // Fetch metadata for each token
                let meta = try await sendRPCRequest(
                    method: "alchemy_getTokenMetadata",
                    params: [contractAddress]
                ) { result in
                    guard
                        let response = result as? [String: Any],
                        let symbol = response["symbol"] as? String,
                        let decimalsString = response["decimals"] as? Int64,
                        let logo = response["logo"] as? String
                    else {
                        throw RpcServiceError.rpcError(code: -1, message: "Invalid JSON for alchemy_getTokenMetadata")
                    }
                    
                    return CoinMeta(
                        chain: nativeToken.chain,
                        ticker: symbol,
                        logo: logo,
                        decimals: Int(decimalsString),
                        priceProviderId: "",
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                }
                
                tokenMetadata.append(meta)
            }
            
            return tokenMetadata
            
        } catch {
            print("Error fetching tokens: \(error)")
            return []
        }
    }

    
}
