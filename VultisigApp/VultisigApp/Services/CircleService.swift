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
    case walletNotDeployed
}

extension CircleServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDetails:
            return NSLocalizedString("circleErrorInvalidDetails", comment: "Invalid details")
        case .keysignError(let message):
            return message
        case .walletNotDeployed:
            return NSLocalizedString("circleErrorWalletNotDeployed", comment: "Wallet not deployed")
        }
    }
}

struct CircleConstants {
    static let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    static let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
}

struct CircleService {
    static let shared = CircleService()
    
    private init() {}
    
    // MARK: - Payload Generation
    
    /// Generates the payload required for keysign
    func getKeysignPayload(
        encryptionKeyHex: String,
        vault: Vault,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        fee: BigInt,
        chainSpecific: BlockChainSpecific
    ) async throws -> KeysignMessage {
        
        guard let coin = vault.coins.first(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            throw CircleServiceError.invalidDetails
        }
        
        let keysignPayload = KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
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
    
    /// Generates the withdrawal values for Circle MSCA execute call
    func getWithdrawalValues(
        vault: Vault,
        recipientAddress: String,
        amount: BigInt,
        info: CircleViewLogic.CircleWithdrawalInfo,
        isNative: Bool = false
    ) async throws -> (to: String, amount: BigInt, data: Data) {
        
        let usdcContract = info.usdcContract
        
        guard let recipientAddr = AnyAddress(string: recipientAddress, coin: .ethereum) else {
            throw CircleServiceError.keysignError("Invalid Recipient Address")
        }
        
        var targetHelperIndex: Data
        var valueHelper: BigInt
        var dataHelper: Data
        
        if isNative {
            // Native ETH Transfer: execute(recipient, amount, emptyData)
            targetHelperIndex = recipientAddr.data
            valueHelper = amount
            dataHelper = Data()
        } else {
            // ERC20 Token Transfer (USDC): execute(tokenContract, 0, transfer(recipient, amount))
            guard let usdcAddr = AnyAddress(string: usdcContract, coin: .ethereum) else {
                throw CircleServiceError.keysignError("Invalid USDC Contract Address")
            }
            
            // Encode Inner Call: USDC transfer(to, amount)
            let transferFunc = EthereumAbiFunction(name: "transfer")
            transferFunc.addParamAddress(val: recipientAddr.data, isOutput: false)
            transferFunc.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
            
            targetHelperIndex = usdcAddr.data
            valueHelper = BigInt(0)
            dataHelper = EthereumAbi.encode(fn: transferFunc)
        }
        
        // Encode Outer Call: MSCA execute(target, value, data)
        let executeFunc = EthereumAbiFunction(name: "execute")
        executeFunc.addParamAddress(val: targetHelperIndex, isOutput: false)
        executeFunc.addParamUInt256(val: valueHelper.serializeForEvm(), isOutput: false)
        executeFunc.addParamBytes(val: dataHelper, isOutput: false)
        
        let executeData = EthereumAbi.encode(fn: executeFunc)
        
        guard let circleWalletAddress = vault.circleWalletAddress else {
            throw CircleServiceError.invalidDetails
        }
        
        return (to: circleWalletAddress, amount: BigInt(0), data: executeData)
    }
}
