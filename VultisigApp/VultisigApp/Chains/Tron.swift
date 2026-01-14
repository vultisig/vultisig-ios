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

enum TronHelper {
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        // For TRX swaps, we use the same logic as regular transactions but with swap memo
        return try getPreSignedInputData(keysignPayload: keysignPayload)
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TRX" else {
            throw HelperError.runtimeError("coin is not TRX")
        }
        
        guard case .Tron(let timestamp, let expiration, let blockHeaderTimestamp, let blockHeaderNumber, let blockHeaderVersion, let blockHeaderTxTrieRoot, let blockHeaderParentHash, let blockHeaderWitnessAddress, let gasEstimation) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Tron chain specific")
        }
        
        guard Data(hexString: keysignPayload.coin.hexPublicKey) != nil else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        // Dispatch based on contract payload type (dApp integration)
        if let transferPayload = keysignPayload.tronTransferContractPayload {
            return try buildTronTransferContractInput(
                payload: transferPayload,
                timestamp: timestamp, expiration: expiration,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress,
                memo: keysignPayload.memo
            )
        }
        
        if let smartContractPayload = keysignPayload.tronTriggerSmartContractPayload {
            return try buildTronSmartContractInput(
                payload: smartContractPayload,
                timestamp: timestamp, expiration: expiration, gasEstimation: gasEstimation,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress,
                memo: keysignPayload.memo
            )
        }
        
        if let assetPayload = keysignPayload.tronTransferAssetContractPayload {
            return try buildTronTransferAssetInput(
                payload: assetPayload,
                timestamp: timestamp, expiration: expiration, gasEstimation: gasEstimation,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress,
                memo: keysignPayload.memo
            )
        }
        
        // FreezeBalanceV2 (Stake 2.0) - detect from memo
        if let memo = keysignPayload.memo, memo.hasPrefix("FREEZE:") {
            let resourceString = String(memo.dropFirst("FREEZE:".count))
            return try buildTronFreezeBalanceV2Input(
                ownerAddress: keysignPayload.coin.address,
                frozenBalance: keysignPayload.toAmount,
                resource: resourceString,
                timestamp: timestamp, expiration: expiration,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress
            )
        }
        
        // UnfreezeBalanceV2 (Stake 2.0) - detect from memo
        if let memo = keysignPayload.memo, memo.hasPrefix("UNFREEZE:") {
            let resourceString = String(memo.dropFirst("UNFREEZE:".count))
            return try buildTronUnfreezeBalanceV2Input(
                ownerAddress: keysignPayload.coin.address,
                unfreezeBalance: keysignPayload.toAmount,
                resource: resourceString,
                timestamp: timestamp, expiration: expiration,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress
            )
        }
        
        // Fallback: validate toAddress for regular transfers
        guard AnyAddress(string: keysignPayload.toAddress, coin: .tron) != nil else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        // Existing native/TRC20 transfer logic
        if keysignPayload.coin.isNativeToken {
            
            let contract = TronTransferContract.with {
                $0.ownerAddress = keysignPayload.coin.address
                $0.toAddress = keysignPayload.toAddress
                $0.amount = Int64(keysignPayload.toAmount)
            }
            
            let input = try TronSigningInput.with {
                $0.transaction = try TronTransaction.with {
                    $0.contractOneof = .transfer(contract)
                    $0.timestamp = Int64(timestamp)
                    
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                    
                    $0.blockHeader = try buildBlockHeader(
                        timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                        version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                        parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                    )
                    $0.expiration = Int64(expiration)
                }
            }
            
            return try input.serializedData()
            
        } else {
            
            let contract = TronTransferTRC20Contract.with {
                $0.toAddress = keysignPayload.toAddress
                $0.contractAddress = keysignPayload.coin.contractAddress
                $0.ownerAddress = keysignPayload.coin.address
                $0.amount = keysignPayload.toAmount.serialize()
            }
            
            let input = try TronSigningInput.with {
                $0.transaction = try TronTransaction.with {
                    $0.feeLimit = Int64(gasEstimation)
                    $0.transferTrc20Contract = contract
                    $0.timestamp = Int64(timestamp)
                    $0.blockHeader = try buildBlockHeader(
                        timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                        version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                        parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                    )
                    $0.expiration = Int64(expiration)
                    if let memo = keysignPayload.memo {
                        $0.memo = memo
                    }
                }
            }
            
            return try input.serializedData()
            
        }
        
    }
    
    // MARK: - Block Header Helper
    
    private static func buildBlockHeader(
        timestamp: UInt64, number: UInt64, version: UInt64,
        txTrieRoot: String, parentHash: String, witnessAddress: String
    ) throws -> TronBlockHeader {
        guard let txTrieRootData = Data(hexString: txTrieRoot),
              let parentHashData = Data(hexString: parentHash),
              let witnessAddressData = Data(hexString: witnessAddress) else {
            throw HelperError.runtimeError("Invalid block header hex data")
        }
        return TronBlockHeader.with {
            $0.timestamp = Int64(timestamp)
            $0.number = Int64(number)
            $0.version = Int32(version)
            $0.txTrieRoot = txTrieRootData
            $0.parentHash = parentHashData
            $0.witnessAddress = witnessAddressData
        }
    }
    
    // MARK: - Contract Payload Builders (dApp Integration)
    
    private static func buildTronTransferContractInput(
        payload: TronTransferContractPayload,
        timestamp: UInt64, expiration: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String,
        memo: String?
    ) throws -> Data {
        guard let amount = Int64(payload.amount) else {
            throw HelperError.runtimeError("Invalid transfer amount: \(payload.amount)")
        }
        let contract = TronTransferContract.with {
            $0.ownerAddress = payload.ownerAddress
            $0.toAddress = payload.toAddress
            $0.amount = amount
        }
        
        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .transfer(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
                if let memo { $0.memo = memo }
            }
        }
        return try input.serializedData()
    }
    
    private static func buildTronSmartContractInput(
        payload: TronTriggerSmartContractPayload,
        timestamp: UInt64, expiration: UInt64, gasEstimation: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String,
        memo: String?
    ) throws -> Data {
        let contract = TronTriggerSmartContract.with {
            $0.ownerAddress = payload.ownerAddress
            $0.contractAddress = payload.contractAddress
            if let callValue = payload.callValue {
                $0.callValue = Int64(callValue) ?? 0
            }
            if let callTokenValue = payload.callTokenValue {
                $0.callTokenValue = Int64(callTokenValue) ?? 0
            }
            if let tokenId = payload.tokenId {
                $0.tokenID = Int64(tokenId)
            }
            if let data = payload.data {
                // Handle hex or UTF-8 data
                if data.hasPrefix("0x") {
                    $0.data = Data(hexString: String(data.dropFirst(2))) ?? Data()
                } else if data.allSatisfy({ $0.isHexDigit }) {
                    $0.data = Data(hexString: data) ?? Data()
                } else {
                    $0.data = Data(data.utf8)
                }
            }
        }
        
        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .triggerSmartContract(contract)
                $0.feeLimit = Int64(gasEstimation)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
                if let memo { $0.memo = memo }
            }
        }
        return try input.serializedData()
    }
    
    private static func buildTronTransferAssetInput(
        payload: TronTransferAssetContractPayload,
        timestamp: UInt64, expiration: UInt64, gasEstimation: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String,
        memo: String?
    ) throws -> Data {
        let contract = TronTransferAssetContract.with {
            $0.ownerAddress = payload.ownerAddress
            $0.toAddress = payload.toAddress
            $0.amount = Int64(payload.amount) ?? 0
            $0.assetName = payload.assetName
        }
        
        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .transferAsset(contract)
                $0.feeLimit = Int64(gasEstimation)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
                if let memo { $0.memo = memo }
            }
        }
        return try input.serializedData()
    }
    
    // MARK: - FreezeBalanceV2 (Stake 2.0)
    
    private static func buildTronFreezeBalanceV2Input(
        ownerAddress: String,
        frozenBalance: BigInt,
        resource: String,
        timestamp: UInt64, expiration: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String
    ) throws -> Data {
        let contract = TronFreezeBalanceV2Contract.with {
            $0.ownerAddress = ownerAddress
            $0.frozenBalance = Int64(frozenBalance)
            $0.resource = resource
        }
        
        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .freezeBalanceV2(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
            }
        }
        return try input.serializedData()
    }
    
    // MARK: - UnfreezeBalanceV2 (Stake 2.0)
    
    private static func buildTronUnfreezeBalanceV2Input(
        ownerAddress: String,
        unfreezeBalance: BigInt,
        resource: String,
        timestamp: UInt64, expiration: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String
    ) throws -> Data {
        let contract = TronUnfreezeBalanceV2Contract.with {
            $0.ownerAddress = ownerAddress
            $0.unfreezeBalance = Int64(unfreezeBalance)
            $0.resource = resource
        }
        
        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .unfreezeBalanceV2(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
            }
        }
        return try input.serializedData()
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .tron,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    static func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        guard
            let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey),
            let secp256k1PubKey = PublicKey(data: pubKeyData, type: .secp256k1Extended) else {
            throw CoinFactory.Errors.invalidPublicKey(pubKey: keysignPayload.coin.hexPublicKey)
        }
        let publicKey = secp256k1PubKey.uncompressed
        let inputData = try getPreSignedInputData(
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(
            coinType: .tron,
            txInputData: inputData
        )
        let preSigningOutput = try TxCompilerPreSigningOutput(
            serializedBytes: hashes
        )
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignatureWithRecoveryID(
            preHash: preSigningOutput.dataHash
        )
        guard publicKey
            .verify(signature: signature, message: preSigningOutput.dataHash) else {
            print("fail to verify signature")
            throw HelperError.runtimeError("fail to verify signature")
        }
        
        allSignatures.add(data: signature)
        publicKeys.add(data: publicKey.data)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .tron,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        
        let output = try TronSigningOutput(
            serializedBytes: compileWithSignature
        )
        
        if !output.errorMessage.isEmpty {
            print(output.errorMessage)
            throw HelperError.runtimeError("fail to sign transaction")
        }
        
        let result = SignedTransactionResult(rawTransaction: output.json,
                                             transactionHash: output.id.hexString)
        
        return result
    }
}

