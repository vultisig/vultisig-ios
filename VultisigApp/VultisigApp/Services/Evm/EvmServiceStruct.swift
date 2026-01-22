//
//  EvmServiceStruct.swift
//  VultisigApp
//
//  Refactored to use struct instead of classes
//

import Foundation
import BigInt

struct EvmServiceStruct {
    let config: EvmServiceConfig
    private let rpcService: RpcServiceStruct

    init(config: EvmServiceConfig) throws {
        self.config = config
        self.rpcService = try RpcServiceStruct(config.rpcEndpoint)
    }

    // MARK: - Balance Operations

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            let balance = try await fetchBalance(address: address)
            return String(balance)
        } else {
            let balance = try await fetchERC20TokenBalance(
                contractAddress: coin.contractAddress,
                walletAddress: address
            )
            return String(balance)
        }
    }

    func getCode(address: String) async throws -> String {
        return try await rpcService.strRpcCall(method: "eth_getCode", params: [address, "latest"])
    }

    /// Fetches the owner of a contract using ERC-173 owner() function
    /// Returns nil if the contract doesn't implement owner() or call fails
    func fetchContractOwner(contractAddress: String) async -> String? {
        // owner() function selector: 0x8da5cb5b
        let data = "0x8da5cb5b"

        let params: [Any] = [
            ["to": contractAddress, "data": data],
            "latest"
        ]

        do {
            let result = try await rpcService.strRpcCall(method: "eth_call", params: params)

            // Result should be a 32-byte hex string (64 chars + 0x prefix)
            // The address is in the last 20 bytes (40 chars)
            let cleanedHex = result.stripHexPrefix()

            guard cleanedHex.count >= 40 else {
                return nil
            }

            // Extract the last 40 characters (20 bytes = address)
            let addressHex = String(cleanedHex.suffix(40))

            // Check if it's a zero address
            if addressHex == String(repeating: "0", count: 40) {
                return "0x0000000000000000000000000000000000000000"
            }

            return "0x" + addressHex
        } catch {
            return nil
        }
    }

    // MARK: - Gas Operations

    func getGasInfo(fromAddress: String, mode: FeeMode) async throws -> (gasPrice: BigInt, priorityFee: BigInt, nonce: Int64) {
        async let gasPrice = fetchGasPrice()
        async let nonce = fetchNonce(address: fromAddress)
        async let priorityFeeMap = fetchMaxPriorityFeesPerGas()

        let gasPriceValue = try await gasPrice
        let priorityFeeMapValue = try await priorityFeeMap
        let nonceValue = try await nonce

        var priorityFee = priorityFeeMapValue[mode] ?? .zero
        // Ensure priority fee does not exceed the gas price when only legacy gasPrice is available on chain
        if priorityFee > gasPriceValue {
            priorityFee = gasPriceValue
        }

        return (gasPriceValue, priorityFee, Int64(nonceValue))
    }

    func fetchMaxPriorityFeesPerGas() async throws -> [FeeMode: BigInt] {
        let history = try await getFeeHistory()

        func priorityFeesMap(low: BigInt, normal: BigInt, fast: BigInt) -> [FeeMode: BigInt] {
            return [.safeLow: low, .normal: normal, .fast: fast]
        }

        guard !history.isEmpty else {
            let value = try await fetchMaxPriorityFeePerGas()
            return priorityFeesMap(low: value, normal: value, fast: value)
        }

        let low = history[0]
        let normal = history[history.count / 2]
        let fast = history[history.count - 1]

        return priorityFeesMap(low: low, normal: normal, fast: fast)
    }

    func getFeeHistory() async throws -> [BigInt] {
        return try await rpcService.sendRPCRequest(method: "eth_feeHistory", params: [10, "latest", [5]]) { result in
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
        return try await rpcService.sendRPCRequest(method: "eth_getBlockByNumber", params: ["latest", true]) { result in
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

    // MARK: - Transaction Operations

    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        return try await rpcService.strRpcCall(method: "eth_sendRawTransaction", params: [hexWithPrefix])
    }

    func estimateGasForEthTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
        // Convert the memo to hex (if present). Assume memo is a String.
        let memoDataHex = memo?.data(using: .utf8)?.map { byte in String(format: "%02x", byte) }.joined() ?? ""

        let transactionObject: [String: Any] = [
            "from": senderAddress,
            "to": recipientAddress,
            "value": value.toHexString(), // Convert value to hex string
            "data": "0x" + memoDataHex // Include the memo in the data field, if present
        ]

        return try await rpcService.intRpcCall(method: "eth_estimateGas", params: [transactionObject])
    }

    func estimateGasForERC20Transfer(senderAddress: String, contractAddress: String, recipientAddress: String, value: BigInt) async throws -> BigInt {
        let data = constructERC20TransferData(recipientAddress: recipientAddress, value: value)

        let transactionObject: [String: Any] = [
            "from": senderAddress,
            "to": contractAddress,
            "value": "0x0",
            "data": data
        ]

        return try await rpcService.intRpcCall(method: "eth_estimateGas", params: [transactionObject])
    }

    func estimateGasLimitForSwap(senderAddress: String, toAddress: String, value: BigInt, data: String) async throws -> BigInt {
        let transactionObject: [String: Any] = [
            "from": senderAddress,
            "to": toAddress,
            "value": value.toHexString(),
            "data": data
        ]

        return try await rpcService.intRpcCall(method: "eth_estimateGas", params: [transactionObject])
    }

    // MARK: - Token Operations

    func fetchERC20TokenBalance(contractAddress: String, walletAddress: String) async throws -> BigInt {
        // Function signature hash of `balanceOf(address)` is `0x70a08231`
        // The wallet address is stripped of '0x', left-padded with zeros to 64 characters
        let paddedWalletAddress = String(walletAddress.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
        let data = "0x70a08231" + paddedWalletAddress

        let params: [Any] = [
            ["to": contractAddress, "data": data],
            "latest"
        ]

        return try await rpcService.intRpcCall(method: "eth_call", params: params)
    }

    func fetchAllowance(contractAddress: String, owner: String, spender: String) async throws -> BigInt {
        let paddedOwner = String(owner.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
        let paddedSpender = String(spender.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")

        let data = "0xdd62ed3e" + paddedOwner + paddedSpender
        let params: [Any] = [["to": contractAddress, "data": data], "latest"]

        return try await rpcService.intRpcCall(method: "eth_call", params: params)
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
            return (.empty, .empty, .zero)
        }
    }

    func getTokens(nativeToken: CoinMeta, address: String) async -> [CoinMeta] {
        return await config.tokenProvider.getTokens(
            nativeToken: nativeToken,
            address: address,
            rpcService: rpcService
        )
    }

    // MARK: - Private Helpers

    private func fetchERC20Data(methodId: String, contractAddress: String) async throws -> String {
        let params: [Any] = [
            ["to": contractAddress, "data": methodId],
            "latest"
        ]
        return try await rpcService.strRpcCall(method: "eth_call", params: params)
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
        return try await rpcService.intRpcCall(method: "eth_getBalance", params: [address, "latest"])
    }

    private func fetchMaxPriorityFeePerGas() async throws -> BigInt {
        return try await rpcService.intRpcCall(method: "eth_maxPriorityFeePerGas", params: []) // WEI
    }

    private func fetchNonce(address: String) async throws -> BigInt {
        return try await rpcService.intRpcCall(method: "eth_getTransactionCount", params: [address, "latest"])
    }

    private func fetchGasPrice() async throws -> BigInt {
        return try await rpcService.intRpcCall(method: "eth_gasPrice", params: [])
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
        return try await rpcService.sendRPCRequest(method: "zks_estimateFee", params: [["from": fromAddress, "to": toAddress, "data": data]]) { result in
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

    // MARK: - Static Helper for Standard Token Fetching

    static func getTokensStandard(nativeToken: CoinMeta, address: String, rpcService: RpcServiceStruct) async -> [CoinMeta] {
        // Try alchemy_getTokenBalances first (for chains that support it)
        do {
            let tokenBalances: [[String: Any]] = try await rpcService.sendRPCRequest(
                method: "alchemy_getTokenBalances",
                params: [address]
            ) { result in
                guard
                    let response = result as? [String: Any],
                    let tokenBalances = response["tokenBalances"] as? [[String: Any]]
                else {
                    return []
                }

                return tokenBalances
            }

            // Process tokens from Alchemy
            var tokenMetadata: [CoinMeta] = []

            for tokenBalance in tokenBalances {
                guard let contractAddress = tokenBalance["contractAddress"] as? String else {
                    continue
                }

                // Fetch metadata for each token
                let meta: CoinMeta? = try await rpcService.sendRPCRequest(
                    method: "alchemy_getTokenMetadata",
                    params: [contractAddress]
                ) { result in
                    guard
                        let response = result as? [String: Any],
                        let symbol = response["symbol"] as? String,
                        !symbol.isEmpty
                    else {
                        return nil
                    }

                    let decimals: Int
                    if let decimalsInt = response["decimals"] as? Int {
                        decimals = decimalsInt
                    } else if let decimalsInt64 = response["decimals"] as? Int64 {
                        decimals = Int(decimalsInt64)
                    } else {
                        return nil
                    }

                    let tokenFromTokenStore = TokensStore.TokenSelectionAssets.first(where: { token in
                        token.chain == nativeToken.chain &&
                        token.ticker == symbol &&
                        token.contractAddress.lowercased() == contractAddress.lowercased()
                    })

                    let logo = tokenFromTokenStore?.logo ?? response["logo"] as? String ?? ""

                    return CoinMeta(
                        chain: nativeToken.chain,
                        ticker: symbol,
                        logo: logo,
                        decimals: decimals,
                        priceProviderId: tokenFromTokenStore?.priceProviderId ?? "",
                        contractAddress: contractAddress,
                        isNativeToken: false
                    )
                }

                if let coinMeta = meta {
                    tokenMetadata.append(coinMeta)
                }
            }

            return tokenMetadata

        } catch {
            // Fallback: Check known tokens from TokensStore using standard RPC methods
            return await getTokensFallback(nativeToken: nativeToken, address: address, rpcService: rpcService)
        }
    }

    // Fallback method: Check balance of known tokens from TokensStore
    private static func getTokensFallback(nativeToken: CoinMeta, address: String, rpcService: RpcServiceStruct) async -> [CoinMeta] {
        // Get all known tokens for this chain from TokensStore
        let knownTokens = TokensStore.TokenSelectionAssets.filter { token in
            token.chain == nativeToken.chain && !token.isNativeToken && !token.contractAddress.isEmpty
        }

        guard !knownTokens.isEmpty else {
            return []
        }

        var tokensWithBalance: [CoinMeta] = []

        // Check balance for each known token in parallel
        await withTaskGroup(of: (CoinMeta, BigInt?).self) { group in
            for token in knownTokens {
                group.addTask {
                    do {
                        // Function signature for balanceOf(address) is 0x70a08231
                        let paddedAddress = String(address.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")
                        let data = "0x70a08231" + paddedAddress

                        let params: [Any] = [
                            ["to": token.contractAddress, "data": data],
                            "latest"
                        ]

                        let balance = try await rpcService.intRpcCall(method: "eth_call", params: params)

                        return (token, balance)
                    } catch {
                        // If balance check fails, assume zero balance
                        return (token, nil)
                    }
                }
            }

            for await (token, balance) in group {
                // Only include tokens with non-zero balance
                if let balance = balance, balance > 0 {
                    tokensWithBalance.append(token)
                }
            }
        }

        return tokensWithBalance
    }

    // MARK: - ENS Resolution

    func resolveENS(ensName: String) async throws -> String {
        let node = ensName.namehash()

        // Get resolver address from the ENS registry
        let resolverAddress = try await fetchResolver(node: node)

        // Fetch the Ethereum address from the resolver
        return try await fetchAddressFromResolver(node: node, resolverAddress: resolverAddress)
    }

    private static let ENS_REGISTRY_ADDRESS = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"

    // Helper method to parse hex string to Data
    private func parseHexToData(_ hex: String, expectedLength: Int) throws -> Data {
        let cleanedHex = hex.stripHexPrefix()
        let expectedHexLength = expectedLength * 2

        guard cleanedHex.count == expectedHexLength else {
            throw RpcEvmServiceError.rpcError(
                code: -1,
                message: "Invalid hex length: expected \(expectedHexLength) characters, got \(cleanedHex.count)"
            )
        }

        var data = Data()
        var index = cleanedHex.startIndex

        while index < cleanedHex.endIndex {
            let nextIndex = cleanedHex.index(index, offsetBy: 2)
            guard nextIndex <= cleanedHex.endIndex else { break }

            let byteString = String(cleanedHex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                throw RpcEvmServiceError.rpcError(
                    code: -1,
                    message: "Invalid hex character in byte string: \(byteString)"
                )
            }

            data.append(byte)
            index = nextIndex
        }

        guard data.count == expectedLength else {
            throw RpcEvmServiceError.rpcError(
                code: -1,
                message: "Invalid data length: expected \(expectedLength) bytes, got \(data.count)"
            )
        }

        return data
    }

    // Helper method to fetch resolver address for a node
    private func fetchResolver(node: String) async throws -> String {
        let params: [Any] = [
            ["to": EvmServiceStruct.ENS_REGISTRY_ADDRESS, "data": "0x0178b8bf" + node.stripHexPrefix()],
            "latest"
        ]

        let result = try await rpcService.strRpcCall(method: "eth_call", params: params)

        // Parse hex to Data (32 bytes)
        let data = try parseHexToData(result, expectedLength: 32)

        // Extract the last 20 bytes, which represent the resolver address
        let resolverAddressData = data.suffix(20)

        // Convert the resolver address data to a hex string and return
        return "0x" + resolverAddressData.map { String(format: "%02x", $0) }.joined()
    }

    // Helper method to fetch address from resolver
    private func fetchAddressFromResolver(node: String, resolverAddress: String) async throws -> String {
        let params: [Any] = [
            ["to": resolverAddress, "data": "0x3b3b57de" + node.stripHexPrefix()],
            "latest"
        ]

        let result = try await rpcService.strRpcCall(method: "eth_call", params: params)

        // Parse hex to Data (32 bytes)
        let data = try parseHexToData(result, expectedLength: 32)

        // Extract the last 20 bytes, which represent the Ethereum address
        let addressData = data.suffix(20)

        // Convert the address data to a hex string and return
        return "0x" + addressData.map { String(format: "%02x", $0) }.joined()
    }
}
