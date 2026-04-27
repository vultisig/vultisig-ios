//
//  PolkadotService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 28/04/24.
//

import Foundation
import BigInt
import VultisigCommonData
import WalletCore

class PolkadotService: RpcService {
    static let rpcEndpoint = Endpoint.polkadotServiceRpc
    static let shared = PolkadotService(rpcEndpoint)

    private var cachePolkadotBalance: ThreadSafeDictionary<String, (data: BigInt, timestamp: Date)> = ThreadSafeDictionary()
    private var cachePolkadotGenesisBlockHash: ThreadSafeDictionary<String, (data: String, timestamp: Date)> = ThreadSafeDictionary()

    // System.Account storage key prefix: twox128("System") ++ twox128("Account")
    private static let systemAccountPrefix = "26aa394eea5630e07c48ae0c9558cef7b99d880ec681799c0cf30e8886371da9"

    private func fetchBalance(address: String) async throws -> BigInt {
        let cacheKey = "polkadot-\(address)-balance"
        if let cachedData: BigInt = Utils.getCachedData(cacheKey: cacheKey, cache: cachePolkadotBalance, timeInSeconds: 60*1) {
            return cachedData
        }

        guard let pubkey = AnyAddress(string: address, coin: .polkadot)?.data else {
            return BigInt.zero
        }
        let blake2Hash = Hash.blake2b(data: pubkey, size: 16) // 128-bit
        let storageKey = "0x" + Self.systemAccountPrefix + blake2Hash.toHexString() + pubkey.toHexString()

        let result: String = try await sendRPCRequest(method: "state_getStorage", params: [storageKey]) { result in
            guard let hex = result as? String else {
                return ""
            }
            return hex
        }

        guard !result.isEmpty else {
            return BigInt.zero
        }

        // SCALE AccountInfo (frame_system + pallet_balances v47):
        //   nonce(u32) + consumers(u32) + providers(u32) + sufficients(u32)
        //   + AccountData { free(u128), reserved(u128), frozen(u128), flags(u128) }
        // `free` is always at byte offset 16, length 16 (u128 LE) — stable across
        // the misc_frozen/fee_frozen -> frozen/flags runtime migration since
        // `free` is always the first AccountData field.
        let hex = result.stripHexPrefix()
        guard hex.count >= 64 else { return BigInt.zero }

        // free balance at bytes 16-31 (hex chars 32-63), u128 little-endian
        let freeHex = String(hex[hex.index(hex.startIndex, offsetBy: 32)..<hex.index(hex.startIndex, offsetBy: 64)])
        var beHex = ""
        for i in stride(from: freeHex.count - 2, through: 0, by: -2) {
            let start = freeHex.index(freeHex.startIndex, offsetBy: i)
            let end = freeHex.index(start, offsetBy: 2)
            beHex += String(freeHex[start..<end])
        }

        let balance = BigInt(beHex, radix: 16) ?? BigInt.zero
        self.cachePolkadotBalance.set(cacheKey, (data: balance, timestamp: Date()))
        return balance
    }

    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "system_accountNextIndex", params: [address])
    }

    private func fetchBlockHash() async throws -> String {
        return try await strRpcCall(method: "chain_getBlockHash", params: [])
    }

    private func fetchGenesisBlockHash() async throws -> String {
        let cacheKey = "polkadot-chain_getBlockHash-genesis"
        if let cachedData: String = Utils.getCachedData(cacheKey: cacheKey, cache: cachePolkadotGenesisBlockHash, timeInSeconds: 60*60*24) {
            return cachedData
        }

        let genesis = try await strRpcCall(method: "chain_getBlockHash", params: [0])
        self.cachePolkadotGenesisBlockHash.set(cacheKey, (data: genesis, timestamp: Date()))
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

    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        let result = try await strRpcCall(method: "author_submitExtrinsic", params: [hexWithPrefix])
        return result
    }

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

    func getPartialFee(serializedTransaction: String) async throws -> BigInt {
        let hexWithPrefix = serializedTransaction.hasPrefix("0x") ? serializedTransaction : "0x\(serializedTransaction)"

        return try await sendRPCRequest(method: "payment_queryInfo", params: [hexWithPrefix]) { result in
            // Handle error message string (from sendRPCRequest error handling)
            if let errorMessage = result as? String {
                throw RpcServiceError.rpcError(code: 500, message: "RPC error: \(errorMessage)")
            }

            guard let resultDict = result as? [String: Any] else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert the RPC result to Dictionary. Got type: \(type(of: result))")
            }

            // Check for error in result
            if let error = resultDict["error"] as? [String: Any] {
                let errorMessage = error["message"] as? String ?? "Unknown error"
                let errorCode = error["code"] as? Int ?? -1
                throw RpcServiceError.rpcError(code: errorCode, message: errorMessage)
            }

            guard let partialFeeString = resultDict["partialFee"] as? String else {
                throw RpcServiceError.rpcError(code: 404, message: "partialFee not found in the response. Available keys: \(resultDict.keys)")
            }

            guard let partialFee = BigInt(partialFeeString) else {
                throw RpcServiceError.rpcError(code: 500, message: "Error to convert partialFee to BigInt: '\(partialFeeString)'")
            }

            return partialFee
        }
    }

    func calculateDynamicFee(fromAddress: String, toAddress: String, amount: BigInt, memo: String? = nil) async throws -> BigInt {
        // Validate and use a default address if toAddress is empty or invalid
        let validToAddress: String
        if toAddress.isEmpty {
            validToAddress = fromAddress
        } else {
            // Try to validate the address format
            if AnyAddress(string: toAddress, coin: .polkadot) != nil {
                validToAddress = toAddress
            } else {
                validToAddress = fromAddress
            }
        }

        let gasInfo = try await getGasInfo(fromAddress: fromAddress)

        guard let polkadotCoin = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .polkadot && $0.isNativeToken }) else {
            throw HelperError.runtimeError("Polkadot coin not found")
        }

        let coin = Coin(asset: polkadotCoin, address: fromAddress, hexPublicKey: "")

        let keysignPayload = KeysignPayload(
            coin: coin,
            toAddress: validToAddress,
            toAmount: amount,
            chainSpecific: .Polkadot(
                recentBlockHash: gasInfo.recentBlockHash,
                nonce: UInt64(gasInfo.nonce),
                currentBlockNumber: gasInfo.currentBlockNumber,
                specVersion: gasInfo.specVersion,
                transactionVersion: gasInfo.transactionVersion,
                genesisHash: gasInfo.genesisHash
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: "",
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )

        let serializedTransaction: String
        do {
            serializedTransaction = try PolkadotHelper.getZeroSignedTransaction(keysignPayload: keysignPayload)
        } catch {
            throw error
        }

        var partialFee = BigInt(250000000)
        do {
            partialFee = try await getPartialFee(serializedTransaction: serializedTransaction)
        } catch {
            print("PolkadotService > calculateDynamicFee > Error fetching partial fee: \(error)")
        }

        return partialFee
    }
}
