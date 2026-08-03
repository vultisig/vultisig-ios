//
//  EvmServiceStruct.swift
//  VultisigApp
//
//  Refactored to use struct instead of classes
//

import Foundation
import BigInt

struct EvmServiceStruct {
    /// Canonical OP-stack `GasPriceOracle` predeploy — identical on every
    /// OP-stack rollup.
    static let gasPriceOracleAddress = "0x420000000000000000000000000000000000000F"
    /// `getL1Fee(bytes)`. Preferred over `getL1FeeUpperBound(uint256)`, which is
    /// the purpose-built API but only exists from Fjord onwards — Blast's oracle
    /// predates it, while `getL1Fee` has been there since Bedrock.
    static let getL1FeeSelector = "49948e0e"
    /// `getOperatorFee(uint256)` — Isthmus and later. Reverts on older oracles,
    /// which is the same answer as "this chain charges no operator fee".
    static let getOperatorFeeSelector = "275aedd2"

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

        guard let normal = history.median() else {
            let value = try await fetchMaxPriorityFeePerGas()
            return priorityFeesMap(low: value, normal: value, fast: value)
        }

        let low = history[0]
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

    /// L1 data-availability fee an OP-stack sequencer charges on top of L2
    /// execution gas, read from the `GasPriceOracle` predeploy. op-geth adds
    /// this to the balance check it runs before executing a transaction, so it
    /// has to be reserved on a native max send or the node rejects the send by
    /// exactly this amount.
    ///
    /// `unsignedTxSize` is the caller's estimate of the UNSIGNED serialized
    /// transaction in bytes — the oracle adds its own 68-byte allowance for the
    /// signature. Only meaningful on `Chain.isOpStack`; anywhere else the
    /// predeploy has no code and the empty result surfaces as a thrown decode
    /// error.
    func fetchOpStackL1DataFee(unsignedTxSize: Int) async throws -> BigInt {
        let payload = Self.l1FeeProbePayload(size: unsignedTxSize)
        let callData = "0x" + Self.getL1FeeSelector + Self.abiEncodedBytesArgument(payload)
        return try await rpcService.intRpcCall(
            method: "eth_call",
            params: [["to": Self.gasPriceOracleAddress, "data": callData], "latest"]
        )
    }

    /// Per-transaction operator fee an OP-stack chain operator may levy from
    /// Isthmus onwards (`gasLimit × operatorFeeScalar / 1e6 + operatorFeeConstant`).
    /// op-geth adds it to the same pre-execution balance check as the L1 data
    /// fee, so a native max send has to reserve it too. Zero on chains whose
    /// operator scalars are unset, and a revert on oracles that predate the
    /// method — which means the same thing.
    func fetchOpStackOperatorFee(gasLimit: BigInt) async throws -> BigInt {
        let callData = "0x" + Self.getOperatorFeeSelector + Self.abiEncodedUInt256(gasLimit)
        return try await rpcService.intRpcCall(
            method: "eth_call",
            params: [["to": Self.gasPriceOracleAddress, "data": callData], "latest"]
        )
    }

    /// Probe bytes handed to `getL1Fee(bytes)` in place of the real serialized
    /// transaction, which isn't built yet when the fee has to be reserved.
    ///
    /// Deliberately **incompressible**: from Fjord onwards the oracle prices the
    /// FastLZ-compressed size of the bytes it is given, so anything with
    /// repeated 3-byte windows reports a fee below what a real transaction
    /// costs. A counter or stride sequence is not enough — it wraps, and the
    /// repeat is compressible: measured against Optimism, a 512-byte stride
    /// payload reports 4.92e9 where random bytes report 9.24e9. This LCG stream
    /// stays deterministic without wrapping, and measures 2.96e9 / 8.85e9 /
    /// 18.19e9 at 160 / 512 / 1024 bytes against random's 2.96e9 / 9.24e9 /
    /// 18.19e9.
    static func l1FeeProbePayload(size: Int) -> Data {
        var state: UInt32 = 0x9E37_79B9
        var bytes = [UInt8]()
        bytes.reserveCapacity(max(0, size))
        for _ in 0..<max(0, size) {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes.append(UInt8((state >> 24) & 0xFF))
        }
        return Data(bytes)
    }

    /// Solidity ABI encoding of a single `uint256` argument.
    static func abiEncodedUInt256(_ value: BigInt) -> String {
        let hex = String(value.magnitude, radix: 16)
        guard hex.count < 64 else { return String(hex.suffix(64)) }
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    /// Solidity ABI encoding of a single dynamic `bytes` argument: head offset,
    /// length, then the payload right-padded to a 32-byte boundary.
    static func abiEncodedBytesArgument(_ payload: Data) -> String {
        let paddedLength = (payload.count + 31) / 32 * 32
        let offset = String(format: "%064x", 32)
        let length = String(format: "%064x", payload.count)
        let body = payload.map { String(format: "%02x", $0) }.joined()
        let padding = String(repeating: "00", count: paddedLength - payload.count)
        return offset + length + body + padding
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

    /// Reads native + ERC20 balances for `walletAddress` in a single `eth_call`
    /// to Multicall3 `aggregate3`. When `includeNative` is set, a `getEthBalance`
    /// call is prepended so the native balance comes back in the same round-trip.
    /// Every sub-call uses `allowFailure = true`, so a reverting/garbage contract
    /// fails on its own without taking its siblings down. Order is the contract for
    /// mapping results back to inputs.
    ///
    /// A failed sub-call is **absent** from `balances` (and leaves `native` nil)
    /// rather than reported as `0`: `aggregate3` returns success at the top level
    /// even when an individual sub-call fails, so this is the only signal the
    /// caller gets, and collapsing it to `0` would persist an empty balance over a
    /// funded coin. Callers must retry an absent entry per-coin.
    func fetchERC20Balances(
        contractAddresses: [String],
        walletAddress: String,
        multicall3Address: String,
        includeNative: Bool
    ) async throws -> (native: BigInt?, balances: [String: BigInt]) {
        try await Self.fetchERC20Balances(
            contractAddresses: contractAddresses,
            walletAddress: walletAddress,
            multicall3Address: multicall3Address,
            includeNative: includeNative,
            rpcService: rpcService
        )
    }

    static func fetchERC20Balances(
        contractAddresses: [String],
        walletAddress: String,
        multicall3Address: String,
        includeNative: Bool,
        rpcService: RpcServiceStruct
    ) async throws -> (native: BigInt?, balances: [String: BigInt]) {
        let paddedWallet = String(walletAddress.dropFirst(2)).paddingLeft(toLength: 64, withPad: "0")

        var calls: [(target: String, callData: String)] = []
        if includeNative {
            // getEthBalance(address) is hosted on the Multicall3 contract itself.
            calls.append((target: multicall3Address, callData: "0x" + Multicall3.getEthBalanceSelector + paddedWallet))
        }
        for contractAddress in contractAddresses {
            calls.append((target: contractAddress, callData: "0x" + Multicall3.balanceOfSelector + paddedWallet))
        }

        let calldata = Multicall3.encodeAggregate3(calls: calls)
        let params: [Any] = [["to": multicall3Address, "data": calldata], "latest"]
        let resultHex = try await rpcService.strRpcCall(method: "eth_call", params: params)
        let decoded = Multicall3.decodeAggregate3Results(hex: resultHex)

        // A short/garbage decode would silently drop balances; treat it as a batch
        // failure so the caller falls back to the per-token path.
        guard let mapped = Multicall3.mapBalances(
            decoded: decoded,
            includeNative: includeNative,
            contractAddresses: contractAddresses
        ) else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Unexpected Multicall3 result count")
        }

        return mapped
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

    // MARK: - Static Helper for Token Discovery Fallback
    //
    // Used by EVM chains that 1inch doesn't index. `EvmCoinFinder` handles
    // the 1inch-supported chains (ethereum/base/arbitrum/polygon/optimism/
    // bsc/avalanche); anything else falls through to this `balanceOf` walk
    // over the chain's TokensStore entries.

    /// Check balance of known tokens from TokensStore via `eth_call balanceOf`.
    /// Returns only the entries with non-zero balance.
    static func getTokensFallback(nativeToken: CoinMeta, address: String, rpcService: RpcServiceStruct) async -> [CoinMeta] {
        // Get all known tokens for this chain from TokensStore
        let knownTokens = TokensStore.TokenSelectionAssets.filter { token in
            token.chain == nativeToken.chain && !token.isNativeToken && !token.contractAddress.isEmpty
        }

        guard !knownTokens.isEmpty else {
            return []
        }

        // An entry absent from `balances` is a failed sub-call, not a zero
        // balance — only trust the batch when every token came back; otherwise
        // fall through to the per-token walk below.
        if let multicall3Address = Multicall3.address(for: nativeToken.chain),
           let result = try? await fetchERC20Balances(
               contractAddresses: knownTokens.map(\.contractAddress),
               walletAddress: address,
               multicall3Address: multicall3Address,
               includeNative: false,
               rpcService: rpcService
           ),
           knownTokens.allSatisfy({ result.balances[$0.contractAddress] != nil }) {
            return knownTokens.filter { (result.balances[$0.contractAddress] ?? 0) > 0 }
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
