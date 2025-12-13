//
//  CircleService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import Foundation
import WalletCore
import BigInt

enum CircleServiceError: Error {
    case invalidDetails
    case keysignError(String)
}

struct CircleService {
    static let shared = CircleService()
    
    private init() {}
    
    // MARK: - Payload Generation
    
    /// Generates the payload required for keysign
    /// - Parameters:
    ///   - encryptionKeyHex: The encryption hex key
    ///   - vault: The vault instance
    ///   - toAddress: Destination address (for withdraw/deposit etc.)
    ///   - amount: Amount to transact
    ///   - memo: Optional memo
    ///   - fee: Gas fee
    ///   - transactionType: Type of transaction (withdraw, claim, etc.)
    ///   - chainSpecific: Chain specific parameters
    func getKeysignPayload(
        encryptionKeyHex: String,
        vault: Vault,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        fee: BigInt,
        chainSpecific: BlockChainSpecific
    ) async throws -> KeysignMessage {
        
        print("CircleService: getKeysignPayload called")
        print("CircleService: Inputs - To: \(toAddress), Amount: \(amount), Fee: \(fee)")

        guard let coin = vault.coins.first(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            print("CircleService: Error - ETH native token not found in vault")
            throw CircleServiceError.invalidDetails
        }
        print("CircleService: Using coin: \(coin.ticker)")
        
        // MCSA uses Ethereum chain (Circle uses Ethereum Mainnet)
        // We reuse Ethereum logic but with specific contract calls if needed
        
        // Basic Payload structure - this mirrors EVM payload generation
        let keysignPayload = KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount, // Amount 0 for the execution call itself (ETH transferred), usually 0 for calling a contract unless sending ETH
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            skipBroadcast: false
        )
        
        print("CircleService: KeysignPayload constructed. Chain: \(coin.chain.name), To: \(keysignPayload.toAddress), Amount: \(keysignPayload.toAmount)")
        
        return KeysignMessage(
            sessionID: UUID().uuidString,
            serviceName: "Circle",
            payload: keysignPayload,
            customMessagePayload: nil,
            encryptionKeyHex: encryptionKeyHex,
            useVultisigRelay: false,
            payloadID: UUID().uuidString
        )
    }
    // MARK: - ABI Encoding Logic
    
    /// Generates the payload required for keysign for a Circle Withdrawal
    /// Wraps USDC transfer inside MSCA execute call
    // MARK: - ABI Encoding Logic
    
    /// Generates the payload required for keysign for a Circle Withdrawal
    /// Wraps USDC transfer inside MSCA execute call
    func getWithdrawalValues(
        vault: Vault,
        recipientAddress: String,
        amount: BigInt,
        info: CircleViewLogic.CircleWithdrawalInfo
    ) async throws -> (to: String, amount: BigInt, data: Data) {
        
        let usdcContract = info.usdcContract
        
        // 0. Validation & Preparation
        guard let recipientAddr = AnyAddress(string: recipientAddress, coin: .ethereum) else {
            throw CircleServiceError.keysignError("Invalid Recipient Address")
        }
        guard let usdcAddr = AnyAddress(string: usdcContract, coin: .ethereum) else {
            throw CircleServiceError.keysignError("Invalid USDC Contract Address")
        }
        
        // 1. Encode Inner Call: USDC transfer(to, amount)
        // Function: transfer(address,uint256)
        let transferFunc = EthereumAbiFunction(name: "transfer")
        transferFunc.addParamAddress(val: recipientAddr.data, isOutput: false)
        transferFunc.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
        
        let transferData = EthereumAbi.encode(fn: transferFunc)
        
        // 2. Encode Outer Call: MSCA execute(target, value, data)
        // Function: execute(address,uint256,bytes)
        let executeFunc = EthereumAbiFunction(name: "execute")
        executeFunc.addParamAddress(val: usdcAddr.data, isOutput: false) // Target
        executeFunc.addParamUInt256(val: BigInt(0).serializeForEvm(), isOutput: false) // Value (0 ETH)
        executeFunc.addParamBytes(val: transferData, isOutput: false) // Data (Inner Call)
        
        let executeData = EthereumAbi.encode(fn: executeFunc)
        
        print("CircleService: Constructed Validated Execute Data: \(executeData.hexString)")
        
        // The transaction is sent TO the Circle Wallet (MSCA) itself
        guard let circleWalletAddress = vault.circleWalletAddress else {
            throw CircleServiceError.invalidDetails
        }
        
        return (to: circleWalletAddress, amount: BigInt(0), data: executeData)
    }
}
