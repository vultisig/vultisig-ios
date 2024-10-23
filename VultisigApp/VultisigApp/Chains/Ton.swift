//
//  TonHelper.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

class TonHelper {
    
    // MARK: - Public Methods
    
    /// Constructs pre-signed input data for staking operations.
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TON" else {
            throw HelperError.runtimeError("coin is not TON")
        }
        
        guard case .Ton(let sequenceNumber, let expireAt, let bounceable) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let transfer = TheOpenNetworkTransfer.with {
            $0.dest = toAddress.description
            $0.amount = UInt64(keysignPayload.toAmount.description) ?? 0
            $0.mode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)
            $0.bounceable = bounceable
            
            $0.customPayload = TheOpenNetworkCustomPayload.with {
                $0.payload = getStakingCustomPayload()
            }
        }
        
        let input = TheOpenNetworkSigningInput.with {
            $0.messages = [transfer]
            $0.sequenceNumber = UInt32(sequenceNumber.description) ?? 0
            $0.expireAt = UInt32(expireAt.description) ?? 0
            $0.walletVersion = TheOpenNetworkWalletVersion.walletV4R2
            $0.publicKey = pubKeyData
        }
        
        return try input.serializedData()
        
    }
    
    /// Constructs pre-signed input data for unstaking operations.
    static func getUnstakingPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        
        guard keysignPayload.coin.chain.ticker == "TON" else {
            throw HelperError.runtimeError("coin is not TON")
        }
        
        guard case .Ton(let sequenceNumber, let expireAt, let bounceable) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("fail to get to address")
        }
        
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        
        let transfer = TheOpenNetworkTransfer.with {
            $0.dest = toAddress.description
            // Minimal amount to cover fees, e.g., 0.05 TON
            $0.amount = 50_000_000
            $0.mode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)
            $0.bounceable = bounceable
            
            $0.customPayload = TheOpenNetworkCustomPayload.with {
                $0.payload = getUnstakingCustomPayload(keysignPayload: keysignPayload)
            }
        }
        
        let input = TheOpenNetworkSigningInput.with {
            $0.messages = [transfer]
            $0.sequenceNumber = UInt32(sequenceNumber.description) ?? 0
            $0.expireAt = UInt32(expireAt.description) ?? 0
            $0.walletVersion = TheOpenNetworkWalletVersion.walletV4R2
            $0.publicKey = pubKeyData
        }
        
        return try input.serializedData()
        
    }
    
    /// Generates the staking custom payload in Base64 encoding.
    static func getStakingCustomPayload() -> String {
        // Staking operation code
        let opCode: UInt32 = 0x4e73744b // addOrdinaryStake
        
        // Construct the cell
        let cellData = try! constructCell(opCode: opCode, amount: nil)
        
        // Encode the cell data in Base64
        let payloadBase64 = cellData.base64EncodedString()
        
        return payloadBase64
    }
    
    /// Generates the unstaking custom payload in Base64 encoding.
    static func getUnstakingCustomPayload(keysignPayload: KeysignPayload) -> String {
        // Unstaking operation code
        let opCode: UInt32 = 0x47657424 // withdrawPart
        
        // Amount to unstake (in nanotons)
        let unstakeAmount: UInt64 = UInt64(keysignPayload.toAmount.description) ?? 0
        
        // Construct the cell with the operation code and amount
        let cellData = try! constructCell(opCode: opCode, amount: unstakeAmount)
        
        // Encode the cell data in Base64
        let payloadBase64 = cellData.base64EncodedString()
        
        return payloadBase64
    }
    
    /// Retrieves the pre-signed image hash.
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print(preSigningOutput.errorMessage)
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }
    
    /// Generates a signed transaction result.
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
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
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
        
        let output = try TheOpenNetworkSigningOutput(serializedData: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: getHashFromRawTransaction(tx: output.encoded))
        
        return result
    }
    
    /// Extracts the hash from a raw transaction.
    static func getHashFromRawTransaction(tx: String) -> String {
        let sig = Data(tx.prefix(64).utf8)
        return sig.base64EncodedString()
    }
    
    // MARK: - Helper Methods and Extensions
    
    /// Encodes a number into a specified byte count in big-endian order.
    static func encodeNumber(_ value: UInt64, byteCount: Int) -> Data {
        var data = Data(count: byteCount)
        for i in 0..<byteCount {
            let shift = UInt64((byteCount - 1 - i) * 8)
            data[i] = UInt8((value >> shift) & 0xFF)
        }
        return data
    }
    
    /// Encodes coins as a variable-length unsigned integer (TL-B VarUint).
    static func encodeCoins(_ amount: UInt64) -> Data {
        var value = amount
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.insert(byte, at: 0)
        } while value != 0
        return Data(bytes)
    }
    
    /// Constructs a BOC cell with the given operation code and optional amount.
    static func constructCell(opCode: UInt32, amount: UInt64?) throws -> Data {
        // Create the cell data bits
        var dataBits = [Bool]()
        
        // Append operation code (32 bits)
        let opCodeBits = opCode.bits(totalBits: 32)
        dataBits.append(contentsOf: opCodeBits)
        
        // Append amount if provided (for unstaking)
        if let amount = amount {
            // Encode amount as varuint
            let amountData = encodeCoins(amount)
            // Convert amountData to bits
            for byte in amountData {
                let byteBits = byte.bits(totalBits: 8)
                dataBits.append(contentsOf: byteBits)
            }
        }
        
        // Compute data size in bits and bytes
        let dataSizeInBits = dataBits.count
        let dataSizeInBytes = (dataSizeInBits + 7) / 8
        let fullBytes = dataSizeInBits % 8 == 0
        
        // Prepare cell descriptors
        let refCount: UInt8 = 0 // No references
        let isExotic: UInt8 = 0 // Ordinary cell
        let levelMask: UInt8 = 0 // Level mask
        let d1 = refCount + (isExotic << 3) + (levelMask << 5)
        
        let d2 = UInt8(dataSizeInBytes * 2 - (fullBytes ? 0 : 1))
        
        // Build the cell content
        var cellContent = Data()
        cellContent.append(d1)
        cellContent.append(d2)
        
        // Convert dataBits to bytes
        var dataBytes = [UInt8](repeating: 0, count: dataSizeInBytes)
        for (index, bit) in dataBits.enumerated() {
            let byteIndex = index / 8
            let bitIndex = 7 - (index % 8)
            if bit {
                dataBytes[byteIndex] |= (1 << bitIndex)
            }
        }
        
        // Handle padding bits if not full bytes
        if !fullBytes {
            let paddingBits = 8 - (dataSizeInBits % 8)
            dataBytes[dataSizeInBytes - 1] |= 1 << (paddingBits - 1)
        }
        
        cellContent.append(contentsOf: dataBytes)
        
        // No references to append since refCount is 0
        
        // Compute total cells size
        let totalCellsSize = UInt64(cellContent.count)
        
        // Compute off_bytes (minimum bytes to represent cell offsets)
        var offBytes = UInt8(1)
        var tempSize = totalCellsSize
        while tempSize > 0xFF {
            offBytes += 1
            tempSize >>= 8
        }
        
        // Compute size_bytes (minimum bytes to represent serialization parameters)
        let serializationParameters = [UInt64(1), UInt64(1), UInt64(0)] // cells_num, roots_num, absent_num
        let maxSerializationParameter = serializationParameters.max() ?? 0
        var sizeBytes = UInt8(1)
        tempSize = maxSerializationParameter
        while tempSize > 0xFF {
            sizeBytes += 1
            tempSize >>= 8
        }
        
        // Ensure sizeBytes fits in 3 bits
        guard sizeBytes <= 7 else {
            throw HelperError.runtimeError("sizeBytes exceeds 3 bits limit")
        }
        
        // Construct the BOC header
        var boc = Data()
        
        // Magic number
        boc.append(contentsOf: [0xB5, 0xEE, 0x9C, 0x72])
        
        // Flags byte with size_bytes embedded in the lower 3 bits
        let hasIdx = false // No index for simplicity
        let hasCrc32 = false
        let hasCacheBits = false
        let flagsByte: UInt8 = (hasIdx ? 1 << 7 : 0) | (hasCrc32 ? 1 << 6 : 0) | (hasCacheBits ? 1 << 5 : 0) | (sizeBytes & 0x07)
        boc.append(flagsByte)
        
        // Append off_bytes
        boc.append(offBytes)
        
        // Encode serialization parameters using size_bytes
        boc.append(encodeNumber(1, byteCount: Int(sizeBytes))) // cells_num = 1
        boc.append(encodeNumber(1, byteCount: Int(sizeBytes))) // roots_num = 1
        boc.append(encodeNumber(0, byteCount: Int(sizeBytes))) // absent_num = 0
        
        // Encode tot_cells_size using off_bytes
        boc.append(encodeNumber(totalCellsSize, byteCount: Int(offBytes))) // tot_cells_size
        
        // Root list (single root at index 0)
        boc.append(encodeNumber(0, byteCount: Int(sizeBytes))) // root cell index 0
        
        // Since hasIdx is false, no index is appended
        
        // Append cell data
        boc.append(cellContent)
        
        // No CRC32, as hasCrc32 is false
        
        return boc
    }
    
    // MARK: - Private Helper Extensions
    
    /// Extension to convert UInt8 to an array of bits.

}
extension UInt8 {
    func bits(totalBits: Int = 8) -> [Bool] {
        var bitsArray = [Bool](repeating: false, count: totalBits)
        for i in 0..<totalBits {
            bitsArray[i] = (self & (1 << (totalBits - 1 - i))) != 0
        }
        return bitsArray
    }
}

/// Extension to convert UInt32 to an array of bits.
extension UInt32 {
    func bits(totalBits: Int = 32) -> [Bool] {
        var bitsArray = [Bool]()
        for i in 0..<totalBits {
            bitsArray.append((self & (1 << (totalBits - 1 - i))) != 0)
        }
        return bitsArray
    }
}
