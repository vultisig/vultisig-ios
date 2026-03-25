//
//  BittensorService.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

class BittensorService: RpcService {
    static let rpcEndpoint = Endpoint.bittensorServiceRpc
    static let shared = BittensorService(rpcEndpoint)

    private var cacheBittensorBalance: ThreadSafeDictionary<String, (data: BigInt, timestamp: Date)> = ThreadSafeDictionary()
    private var cacheBittensorGenesisBlockHash: ThreadSafeDictionary<String, (data: String, timestamp: Date)> = ThreadSafeDictionary()

    // MARK: - Balance via Taostats API

    // System.Account storage key prefix: twox128("System") ++ twox128("Account")
    private static let systemAccountPrefix = "26aa394eea5630e07c48ae0c9558cef7b99d880ec681799c0cf30e8886371da9"

    private func fetchBalance(address: String) async throws -> BigInt {
        let cacheKey = "bittensor-\(address)-balance"
        if let cachedData: BigInt = Utils.getCachedData(cacheKey: cacheKey, cache: cacheBittensorBalance, timeInSeconds: 60) {
            return cachedData
        }

        // Decode SS58 address to raw pubkey, compute storage key
        guard let pubkey = BittensorHelper.ss58Decode(address) else {
            return BigInt.zero
        }
        let blake2Hash = Hash.blake2b(data: pubkey, size: 16) // 128-bit
        let storageKey = "0x" + Self.systemAccountPrefix + blake2Hash.toHexString() + pubkey.toHexString()

        // Query via RPC — no API key needed
        let result: String = try await sendRPCRequest(method: "state_getStorage", params: [storageKey]) { result in
            guard let hex = result as? String else {
                return ""
            }
            return hex
        }

        guard !result.isEmpty else {
            return BigInt.zero
        }

        // Parse SCALE-encoded AccountInfo: nonce(4) + consumers(4) + providers(4) + sufficients(4) + free(16) + ...
        let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard hex.count >= 64 else { return BigInt.zero }

        // free balance at bytes 16-31 (hex chars 32-63), u128 little-endian
        let freeHex = String(hex[hex.index(hex.startIndex, offsetBy: 32)..<hex.index(hex.startIndex, offsetBy: 64)])
        // Reverse byte pairs for LE → BE conversion
        var beHex = ""
        for i in stride(from: freeHex.count - 2, through: 0, by: -2) {
            let start = freeHex.index(freeHex.startIndex, offsetBy: i)
            let end = freeHex.index(start, offsetBy: 2)
            beHex += String(freeHex[start..<end])
        }

        let balance = BigInt(beHex, radix: 16) ?? BigInt.zero
        self.cacheBittensorBalance.set(cacheKey, (data: balance, timestamp: Date()))
        return balance
    }

    // MARK: - RPC Methods (chain metadata)

    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "system_accountNextIndex", params: [address])
    }

    private func fetchBlockHash() async throws -> String {
        return try await strRpcCall(method: "chain_getBlockHash", params: [])
    }

    private func fetchGenesisBlockHash() async throws -> String {
        let cacheKey = "bittensor-chain_getBlockHash-genesis"
        if let cachedData: String = Utils.getCachedData(cacheKey: cacheKey, cache: cacheBittensorGenesisBlockHash, timeInSeconds: 60*60*24) {
            return cachedData
        }

        let genesis = try await strRpcCall(method: "chain_getBlockHash", params: [0])
        self.cacheBittensorGenesisBlockHash.set(cacheKey, (data: genesis, timestamp: Date()))
        return genesis
    }

    private func fetchRuntimeVersion() async throws -> (specVersion: UInt32, transactionVersion: UInt32) {
        return try await sendRPCRequest(method: "state_getRuntimeVersion", params: []) { result in
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
        return try await sendRPCRequest(method: "chain_getHeader", params: []) { result in
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
        do {
            let result = try await strRpcCall(method: "author_submitExtrinsic", params: [hexWithPrefix])
            return result
        } catch {
            // Suppress "Already Imported" errors (multi-device signing, second device gets this)
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("already imported") {
                // Return the hash from the hex data itself
                let extrinsicData = Data(hexString: hex.stripHexPrefix()) ?? Data()
                let txHash = Hash.blake2b(data: extrinsicData, size: 32).toHexString()
                return "0x\(txHash)"
            }
            throw error
        }
    }

    // MARK: - Public API

    func getBalance(address: String) async throws -> String {
        let balance = try await fetchBalance(address: address)
        return String(balance)
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
