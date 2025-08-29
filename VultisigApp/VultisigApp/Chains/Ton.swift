//
//  Ton.Swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum TonHelper {
    
    // The official Telegram Wallet chages a transaction fee of 0.05 TON. So we do it as well.
    static let defaultFee: BigInt = BigInt(0.05 * pow(10, 9))
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TON" else {
            throw HelperError.runtimeError("coin is not TON")
        }
        
        guard case .Ton(let sequenceNumber, let expireAt, let bounceable, let sendMaxAmount, let jettonAddress, let isActiveDestination) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let transfer: TheOpenNetworkTransfer
        
        // Check if this is a jetton transfer
        if !jettonAddress.isEmpty {
            
            // Build jetton transfer
            transfer = try buildJettonTransfer(keysignPayload: keysignPayload, jettonAddress: jettonAddress, isActiveDestination: isActiveDestination)
        } else {
            
            // Build native TON transfer
            guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
                throw HelperError.runtimeError("fail to get to address")
            }
            
            let baseMode = TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue
            var sendMode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | baseMode)
            if sendMaxAmount {
                sendMode = UInt32(TheOpenNetworkSendMode.attachAllContractBalance.rawValue | baseMode)
            }
            
            transfer = TheOpenNetworkTransfer.with {
                $0.dest = toAddress.description
                $0.amount = sendMaxAmount ? 0 : (UInt64(keysignPayload.toAmount.description) ?? 0)
                $0.mode = sendMode
                
                if let memo = keysignPayload.memo {
                    $0.comment = memo
                }
                $0.bounceable = bounceable
            }
        }
        
        let sequenceNumberUInt32 = UInt32(sequenceNumber.description) ?? 0
        let expireAtUInt32 = UInt32(expireAt.description) ?? 0
        
        
        let input = TheOpenNetworkSigningInput.with {
            $0.messages = [transfer]
            $0.sequenceNumber = sequenceNumberUInt32
            $0.expireAt = expireAtUInt32
            $0.walletVersion = TheOpenNetworkWalletVersion.walletV4R2
            $0.publicKey = pubKeyData
        }
        
        let serializedData = try input.serializedData()
        
        return serializedData
    }
    
    static func buildJettonTransfer(keysignPayload: KeysignPayload, jettonAddress: String, isActiveDestination: Bool) throws -> TheOpenNetworkTransfer {
        
        // Convert destination to bounceable, as jettons addresses are always EQ
        let destinationAddress = try convertToUserFriendly(address: keysignPayload.toAddress, bounceable: true, testOnly: false)
        
        guard !jettonAddress.isEmpty else {
            throw HelperError.runtimeError("Jetton address cannot be empty")
        }
        
        // Calculate the sender's jetton wallet address (we send to our own jetton wallet)
        let senderJettonWalletAddress = try calculateJettonWalletAddress(
            masterAddress: jettonAddress,
            ownerAddress: keysignPayload.coin.address
        )
        
        // Always attach 1 nanoton to trigger Jetton Notify
        let forwardAmountMsg: UInt64 = 1
        
        
        let amount = UInt64(keysignPayload.toAmount.description) ?? 0
        
        let jettonTransfer = TheOpenNetworkJettonTransfer.with {
            
            $0.jettonAmount = amount
            $0.responseAddress = keysignPayload.coin.address
            $0.toOwner = destinationAddress
            $0.forwardAmount = forwardAmountMsg
        }
        
        let mode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)
        
        // Attach at least 0.1 TON for fees, consistent with WalletCore example
        let recommendedJettonsAmount: UInt64 = 100_000_000 // 0.1 * 10^9
        
        let transfer = TheOpenNetworkTransfer.with {
            
            $0.amount = recommendedJettonsAmount
            if let memo = keysignPayload.memo {
                $0.comment = memo
            }
            $0.bounceable = true // Jettons always bounceable
            $0.mode = mode
            $0.dest = senderJettonWalletAddress // Send to SENDER's jetton wallet, not master contract
            $0.jettonTransfer = jettonTransfer
        }
        
        
        return transfer
    }
    
    static func convertToUserFriendly(address: String, bounceable: Bool, testOnly: Bool) throws -> String {
        // Convert address to TON format and then to user-friendly format
        guard let anyAddress = AnyAddress(string: address, coin: .ton) else {
            throw HelperError.runtimeError("Invalid TON address: \(address)")
        }
        
        // Use TONAddressConverter to convert to user-friendly format (matching Android implementation)
        guard let convertedAddress = TONAddressConverter.toUserFriendly(address: anyAddress.description, bounceable: bounceable, testnet: testOnly) else {
            throw HelperError.runtimeError("Failed to convert address to user-friendly format")
        }
        
        return convertedAddress
    }
    
    static func calculateJettonWalletAddress(masterAddress: String, ownerAddress: String) throws -> String {
        // Resolve jetton wallet deterministically (owner + master)
        if let resolved = TonService.shared.getJettonWalletAddressSync(ownerAddress: ownerAddress, masterAddress: masterAddress) {
            return resolved
        }
        if let resolved = TonService.shared.getJettonWalletAddressViaRunGetMethodSync(ownerAddress: ownerAddress, masterAddress: masterAddress) {
            return resolved
        }
        throw HelperError.runtimeError("Failed to resolve jetton wallet for owner: \(ownerAddress)")
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        
        if !preSigningOutput.errorMessage.isEmpty {
            
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        
        let result = [preSigningOutput.data.hexString]
        
        return result
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ton,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try TheOpenNetworkSigningOutput(serializedBytes: compileWithSignature)
        print("Ton signed transaction output encoded: \(output.hash.hexString)")
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: output.hash.hexString)
        
        return result
    }
}

