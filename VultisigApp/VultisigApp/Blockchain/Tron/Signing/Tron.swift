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
import OSLog

enum TronHelper {

    static let freezeMemoPrefix = "FREEZE:"
    static let unfreezeMemoPrefix = "UNFREEZE:"

    /// Memo that routes a self-addressed native TRX payload to
    /// `WithdrawExpireUnfreezeContract` — the Stake 2.0 claim that moves every
    /// expired `UnfreezeBalanceV2` entry back into the spendable balance.
    /// Matched exactly (no argument: the contract takes none) and named after
    /// the TRON contract so co-signing platforms can mirror the convention.
    static let withdrawExpireUnfreezeMemo = "WITHDRAW_EXPIRE_UNFREEZE"

    /// These app-local markers select WalletCore system-contract builders and
    /// are never serialized into the transaction data field.
    static func isSystemContractRoutingMemo(_ memo: String) -> Bool {
        memo == withdrawExpireUnfreezeMemo
            || memo.hasPrefix(freezeMemoPrefix)
            || memo.hasPrefix(unfreezeMemoPrefix)
    }

    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        // For TRX swaps, we use the same logic as regular transactions but with swap memo
        return try getPreSignedInputData(keysignPayload: keysignPayload)
    }

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {

        guard keysignPayload.coin.chain == .tron else {
            throw HelperError.runtimeError("coin is not TRX")
        }

        guard case .Tron(let timestamp, let expiration, let blockHeaderTimestamp, let blockHeaderNumber, let blockHeaderVersion, let blockHeaderTxTrieRoot, let blockHeaderParentHash, let blockHeaderWitnessAddress, let gasEstimation, let feeLimit) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Tron chain specific")
        }
        let signedFeeLimit = feeLimit ?? gasEstimation

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
                timestamp: timestamp, expiration: expiration, gasEstimation: signedFeeLimit,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress,
                memo: keysignPayload.memo
            )
        }

        if let assetPayload = keysignPayload.tronTransferAssetContractPayload {
            return try buildTronTransferAssetInput(
                payload: assetPayload,
                timestamp: timestamp, expiration: expiration, gasEstimation: signedFeeLimit,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress,
                memo: keysignPayload.memo
            )
        }
        // FreezeBalanceV2 (Stake 2.0) - detect from memo
        if let memo = keysignPayload.memo, memo.hasPrefix(freezeMemoPrefix) {
            let resourceString = String(memo.dropFirst(freezeMemoPrefix.count))
            guard resourceString == "BANDWIDTH" || resourceString == "ENERGY" else {
                throw HelperError.runtimeError("Invalid TRON resource type: \(resourceString)")
            }
            return try buildTronFreezeBalanceV2Input(
                ownerAddress: keysignPayload.coin.address,
                frozenBalance: keysignPayload.toAmount,
                resource: resourceString,
                timestamp: timestamp, expiration: expiration, gasEstimation: signedFeeLimit,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress
            )
        }

        // UnfreezeBalanceV2 (Stake 2.0) - detect from memo
        if let memo = keysignPayload.memo, memo.hasPrefix(unfreezeMemoPrefix) {
            let resourceString = String(memo.dropFirst(unfreezeMemoPrefix.count))
            guard resourceString == "BANDWIDTH" || resourceString == "ENERGY" else {
                throw HelperError.runtimeError("Invalid TRON resource type: \(resourceString)")
            }
            return try buildTronUnfreezeBalanceV2Input(
                ownerAddress: keysignPayload.coin.address,
                unfreezeBalance: keysignPayload.toAmount,
                resource: resourceString,
                timestamp: timestamp, expiration: expiration, gasEstimation: signedFeeLimit,
                blockHeaderTimestamp: blockHeaderTimestamp, blockHeaderNumber: blockHeaderNumber,
                blockHeaderVersion: blockHeaderVersion, blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
                blockHeaderParentHash: blockHeaderParentHash, blockHeaderWitnessAddress: blockHeaderWitnessAddress
            )
        }
        // WithdrawExpireUnfreeze (Stake 2.0) - detect from memo. The contract
        // sweeps every expired unfreeze entry for the owner and carries no
        // amount, so `toAmount` is deliberately not read here.
        if keysignPayload.memo == withdrawExpireUnfreezeMemo {
            guard keysignPayload.coin.isNativeToken,
                  keysignPayload.toAddress == keysignPayload.coin.address else {
                throw HelperError.runtimeError("TRON withdraw expire unfreeze requires a native TRX payload addressed to the sender")
            }
            return try buildTronWithdrawExpireUnfreezeInput(
                ownerAddress: keysignPayload.coin.address,
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
                    $0.feeLimit = Int64(signedFeeLimit)
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
        timestamp: UInt64, expiration: UInt64, gasEstimation: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String
    ) throws -> Data {
        // Validate frozenBalance is positive and fits in Int64
        guard let safeFrozenBalance = Int64(exactly: frozenBalance), safeFrozenBalance > 0 else {
            throw HelperError.runtimeError("Invalid frozen balance: must be strictly positive and fit in Int64")
        }

        let contract = TronFreezeBalanceV2Contract.with {
            $0.ownerAddress = ownerAddress
            $0.frozenBalance = safeFrozenBalance
            $0.resource = resource
        }

        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .freezeBalanceV2(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.feeLimit = Int64(gasEstimation)
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
        timestamp: UInt64, expiration: UInt64, gasEstimation: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String
    ) throws -> Data {
        // Validate unfreezeBalance is positive
        guard let safeUnfreezeBalance = Int64(exactly: unfreezeBalance), safeUnfreezeBalance > 0 else {
            throw HelperError.runtimeError("Invalid unfreeze balance: must be strictly positive and fit in Int64")
        }

        let contract = TronUnfreezeBalanceV2Contract.with {
            $0.ownerAddress = ownerAddress
            $0.unfreezeBalance = safeUnfreezeBalance
            $0.resource = resource
        }

        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .unfreezeBalanceV2(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                $0.feeLimit = Int64(gasEstimation)
                $0.blockHeader = try buildBlockHeader(
                    timestamp: blockHeaderTimestamp, number: blockHeaderNumber,
                    version: blockHeaderVersion, txTrieRoot: blockHeaderTxTrieRoot,
                    parentHash: blockHeaderParentHash, witnessAddress: blockHeaderWitnessAddress
                )
            }
        }
        return try input.serializedData()
    }

    // MARK: - WithdrawExpireUnfreeze (Stake 2.0)

    private static func buildTronWithdrawExpireUnfreezeInput(
        ownerAddress: String,
        timestamp: UInt64, expiration: UInt64,
        blockHeaderTimestamp: UInt64, blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64, blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String, blockHeaderWitnessAddress: String
    ) throws -> Data {
        let contract = TronWithdrawExpireUnfreezeContract.with {
            $0.ownerAddress = ownerAddress
        }

        let input = try TronSigningInput.with {
            $0.transaction = try TronTransaction.with {
                $0.contractOneof = .withdrawExpireUnfreeze(contract)
                $0.timestamp = Int64(timestamp)
                $0.expiration = Int64(expiration)
                // Stake 2.0 withdraw is a system contract, not a TVM smart-
                // contract call. `fee_limit` caps Energy for TVM execution and
                // therefore has no meaning here. Keeping it at protobuf zero
                // also matches the node-built transaction and gives every
                // co-signer one canonical byte representation.
                $0.feeLimit = 0
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
            Log.chain.other.error("\(preSigningOutput.errorMessage, privacy: .public)")
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    /// Tron addresses derive from the uncompressed (65-byte, `0x04`-prefixed)
    /// secp256k1 key, but a peer device's `KeysignPayload.coin.hexPublicKey`
    /// may legitimately carry the standard compressed (33-byte) form instead
    /// — that's what every other chain stores, and other platforms' Tron
    /// implementations aren't guaranteed to special-case it the way this
    /// app's `CoinFactory` does. Accept either wire format rather than
    /// rejecting a validly-signed cross-device transaction as "invalid".
    static func uncompressedPublicKey(fromHex hex: String) throws -> PublicKey {
        guard let data = Data(hexString: hex) else {
            throw CoinFactory.Errors.invalidPublicKey(pubKey: hex)
        }
        if let extended = PublicKey(data: data, type: .secp256k1Extended) {
            return extended.uncompressed
        }
        guard let compressed = PublicKey(data: data, type: .secp256k1) else {
            throw CoinFactory.Errors.invalidPublicKey(pubKey: hex)
        }
        return compressed.uncompressed
    }

    static func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let publicKey = try uncompressedPublicKey(fromHex: keysignPayload.coin.hexPublicKey)
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
            Log.chain.other.error("fail to verify signature")
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
            Log.chain.other.error("\(output.errorMessage, privacy: .public)")
            throw HelperError.runtimeError("fail to sign transaction")
        }

        let result = SignedTransactionResult(rawTransaction: output.json,
                                             transactionHash: output.id.hexString)

        return result
    }
}
