//
//  BittensorService.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

/// Balance-read seam for the send-verify destination-ED guard
/// (`SendCryptoVerifyLogic.validateBittensorDestinationIfNeeded`), so tests can
/// substitute a stub without exercising `RpcService`'s network layer.
protocol BittensorBalanceFetching {
    func getBalance(address: String) async throws -> String

    /// Distinguishes a confirmed balance (including a legitimate zero for an
    /// account with no ledger entry) from a read that couldn't be
    /// determined — an undecodable address, a malformed RPC response, or a
    /// truncated one. `nil` means unknown. Used only by the destination-ED
    /// guard, which must fail open on unknown rather than reading it as a
    /// confirmed empty destination the way `getBalance` does (`getBalance`
    /// also backs the user's own wallet-balance display via `BalanceService`,
    /// where collapsing an unknown read to zero is the existing, intentional
    /// behavior and must not change).
    func getBalanceIfKnown(address: String) async throws -> BigInt?
}

class BittensorService: RpcService, BittensorBalanceFetching {
    static let rpcEndpoint = Endpoint.bittensorServiceRpc
    static let shared = BittensorService(rpcEndpoint)

    /// Resolves the Bittensor custom RPC override. Injected so the resolved
    /// endpoint is derived from a dependency rather than a global reach-in;
    /// resolution is computed per request so a runtime override change is picked
    /// up live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    init(_ rpcEndpoint: String, resolver: RPCEndpointResolving = CustomRPCStore.shared) {
        self.resolver = resolver
        super.init(rpcEndpoint)
    }

    /// The override-aware JSON-RPC endpoint. Falls back to the baked-in default
    /// (`Endpoint.bittensorServiceRpc`) when no override is set.
    private var resolvedEndpoint: String {
        resolver.url(for: .bittensor) ?? rpcEndpoint
    }

    private var cacheBittensorBalance: ThreadSafeDictionary<String, (data: BigInt, timestamp: Date)> = ThreadSafeDictionary()
    private var cacheBittensorGenesisBlockHash: ThreadSafeDictionary<String, (data: String, timestamp: Date)> = ThreadSafeDictionary()

    // MARK: - Balance via Taostats API

    // System.Account storage key prefix: twox128("System") ++ twox128("Account")
    private static let systemAccountPrefix = "26aa394eea5630e07c48ae0c9558cef7b99d880ec681799c0cf30e8886371da9"

    /// Reads `System.Account` for `address`, distinguishing a confirmed
    /// balance from a read that couldn't be determined. Only the confirmed
    /// path is cached — an undecodable-address or malformed/truncated read
    /// returns `.unknown` on every call, matching the pre-existing behavior
    /// where those cases were never cached either.
    private func fetchBalanceRead(address: String) async throws -> BittensorHelper.AccountStorageRead {
        let cacheKey = "bittensor-\(address)-balance"
        if let cachedData: BigInt = Utils.getCachedData(cacheKey: cacheKey, cache: cacheBittensorBalance, timeInSeconds: 60) {
            return .confirmed(cachedData)
        }

        // Decode SS58 address to raw pubkey, compute storage key
        guard let pubkey = BittensorHelper.ss58Decode(address) else {
            return .unknown
        }
        let blake2Hash = Hash.blake2b(data: pubkey, size: 16) // 128-bit
        let storageKey = "0x" + Self.systemAccountPrefix + blake2Hash.toHexString() + pubkey.toHexString()

        // Query via RPC — no API key needed. `result` is JSON `null` for an
        // absent storage key (Substrate's documented "no value" sentinel) —
        // decoded here as `NSNull`, distinct from any other non-String shape,
        // which is a malformed response rather than a confirmed absence.
        // Cache only confirmed storage values. An absent account stays uncached
        // so funding it is visible on the next read; malformed data never
        // becomes a cached zero.
        let read: (value: BittensorHelper.AccountStorageRead, cacheable: Bool) = try await sendRPCRequest(
            method: "state_getStorage", params: [storageKey], endpoint: resolvedEndpoint
        ) { result in
            if result is NSNull {
                return (BittensorHelper.interpretAccountStorage(nil), false)
            }
            guard let hex = result as? String else {
                return (.unknown, false)
            }
            return (BittensorHelper.interpretAccountStorage(hex), true)
        }

        if read.cacheable, case .confirmed(let balance) = read.value {
            self.cacheBittensorBalance.set(cacheKey, (data: balance, timestamp: Date()))
        }
        return read.value
    }

    private func fetchBalance(address: String) async throws -> BigInt {
        switch try await fetchBalanceRead(address: address) {
        case .confirmed(let balance): return balance
        case .unknown: return .zero
        }
    }

    // MARK: - RPC Methods (chain metadata)

    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "system_accountNextIndex", params: [address], endpoint: resolvedEndpoint)
    }

    private func fetchBlockHash() async throws -> String {
        return try await strRpcCall(method: "chain_getBlockHash", params: [], endpoint: resolvedEndpoint)
    }

    private func fetchGenesisBlockHash() async throws -> String {
        let cacheKey = "bittensor-chain_getBlockHash-genesis"
        if let cachedData: String = Utils.getCachedData(cacheKey: cacheKey, cache: cacheBittensorGenesisBlockHash, timeInSeconds: 60*60*24) {
            return cachedData
        }

        let genesis = try await strRpcCall(method: "chain_getBlockHash", params: [0], endpoint: resolvedEndpoint)
        self.cacheBittensorGenesisBlockHash.set(cacheKey, (data: genesis, timestamp: Date()))
        return genesis
    }

    private func fetchRuntimeVersion() async throws -> (specVersion: UInt32, transactionVersion: UInt32) {
        return try await sendRPCRequest(method: "state_getRuntimeVersion", params: [], endpoint: resolvedEndpoint) { result in
            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary")
            }

            guard let specVersion = resultDict["specVersion"] as? UInt32 else {
                throw RpcServiceError.rpcError(code: 404, message: "specVersion not found in the response")
            }

            guard let transactionVersion = resultDict["transactionVersion"] as? UInt32 else {
                throw RpcServiceError.rpcError(code: 404, message: "transactionVersion not found in the response")
            }

            return (specVersion, transactionVersion)
        }
    }

    private func fetchBlockHeader() async throws -> BigInt {
        return try await sendRPCRequest(method: "chain_getHeader", params: [], endpoint: resolvedEndpoint) { result in
            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary")
            }

            guard let numberString = resultDict["number"] as? String else {
                throw RpcServiceError.rpcError(code: 404, message: "Block number not found in the response")
            }

            guard let bigIntNumber = BigInt(numberString.stripHexPrefix(), radix: 16) else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert block number to BigInt")
            }
            return bigIntNumber
        }
    }

    // MARK: - Broadcast

    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        let result = try await strRpcCall(method: "author_submitExtrinsic", params: [hexWithPrefix], endpoint: resolvedEndpoint)
        return try SubstrateBroadcast.validatedHash(result)
    }

    // MARK: - Public API

    func getBalance(address: String) async throws -> String {
        let balance = try await fetchBalance(address: address)
        return String(balance)
    }

    func getBalanceIfKnown(address: String) async throws -> BigInt? {
        switch try await fetchBalanceRead(address: address) {
        case .confirmed(let balance): return balance
        case .unknown: return nil
        }
    }

    func getGasInfo(fromAddress: String) async throws -> (recentBlockHash: String, currentBlockNumber: BigInt, nonce: Int64, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String) {
        async let recentBlockHash = fetchBlockHash()
        async let nonce = fetchNonce(address: fromAddress)
        async let currentBlockNumber = fetchBlockHeader()
        async let runtime = fetchRuntimeVersion()
        async let genesisHash = fetchGenesisBlockHash()
        return await (try recentBlockHash, try currentBlockNumber, Int64(try nonce), try runtime.specVersion, try runtime.transactionVersion, try genesisHash)
    }
}
