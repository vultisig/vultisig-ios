//
//  BittensorHelper.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum BittensorHelper {

    /// SS58 prefix for Bittensor (generic Substrate)
    static let ss58Prefix: UInt16 = 42

    /// Balances.transfer_allow_death: pallet index 5, call index 0 (allows full balance send)
    static let moduleIndex: UInt8 = 5
    static let methodIndex: UInt8 = 0

    /// Static fallback fee: 200_000 RAO (0.0002 TAO). Actual fees ~130k-150k RAO.
    static let defaultFee: BigInt = 200_000

    // MARK: - SCALE Compact Encoding

    /// Encode a UInt64 in SCALE compact format
    static func compactEncode(_ value: UInt64) -> Data {
        if value <= 63 {
            // Single-byte mode (bits 0..5 = value, bits 6..7 = 00)
            return Data([UInt8(value << 2)])
        } else if value <= 16383 {
            // Two-byte mode (bits 0..13 = value, bits 14..15 = 01)
            let encoded = UInt16(value << 2) | 0x01
            var data = Data(count: 2)
            data[0] = UInt8(encoded & 0xFF)
            data[1] = UInt8(encoded >> 8)
            return data
        } else if value <= 1073741823 {
            // Four-byte mode (bits 0..29 = value, bits 30..31 = 10)
            let encoded = UInt32(value << 2) | 0x02
            var data = Data(count: 4)
            data[0] = UInt8(encoded & 0xFF)
            data[1] = UInt8((encoded >> 8) & 0xFF)
            data[2] = UInt8((encoded >> 16) & 0xFF)
            data[3] = UInt8((encoded >> 24) & 0xFF)
            return data
        } else {
            // Big-integer mode (prefix byte = (byteLen - 4) << 2 | 0x03)
            var val = value
            var bytes: [UInt8] = []
            while val > 0 {
                bytes.append(UInt8(val & 0xFF))
                val >>= 8
            }
            let prefix = UInt8((bytes.count - 4) << 2) | 0x03
            return Data([prefix]) + Data(bytes)
        }
    }

    /// Encode a BigInt in SCALE compact format
    static func compactEncode(_ value: BigInt) -> Data {
        if value <= BigInt(UInt64.max) {
            return compactEncode(UInt64(value))
        }
        // For values larger than UInt64.max
        var val = value
        var bytes: [UInt8] = []
        while val > 0 {
            bytes.append(UInt8(val & 0xFF))
            val >>= 8
        }
        let prefix = UInt8((bytes.count - 4) << 2) | 0x03
        return Data([prefix]) + Data(bytes)
    }

    /// Encode SCALE compact length prefix for a byte array
    static func compactLength(_ length: Int) -> Data {
        return compactEncode(UInt64(length))
    }

    // MARK: - Mortal Era Encoding

    /// Encode a mortal era with the given block number and period
    static func encodeMortalEra(blockNumber: UInt64, period: UInt64 = 64) -> Data {
        // Find the smallest power of 2 >= period, clamped to [4, 65536]
        var calPeriod = max(period, 4)
        calPeriod = min(calPeriod, 65536)
        // Round up to next power of 2
        var p: UInt64 = 4
        while p < calPeriod {
            p <<= 1
        }
        calPeriod = p

        let phase = blockNumber % calPeriod
        let quantizeFactor = max(calPeriod >> 12, 1)
        let quantizedPhase = (phase / quantizeFactor) * quantizeFactor

        // Encode
        // encoded = min(15, max(1, log2(period) - 1)) | (quantizedPhase / quantizeFactor) << 4
        var periodLog2: UInt64 = 0
        var tmp = calPeriod
        while tmp > 1 {
            tmp >>= 1
            periodLog2 += 1
        }
        let clampedLog = min(15, max(1, periodLog2 - 1))
        let encoded = UInt16(clampedLog) | UInt16(quantizedPhase / quantizeFactor) << 4

        var data = Data(count: 2)
        data[0] = UInt8(encoded & 0xFF)
        data[1] = UInt8(encoded >> 8)
        return data
    }

    // MARK: - SS58 Address Encoding/Decoding

    /// Decode an SS58 address to its raw public key bytes (32 bytes for ed25519)
    static func ss58Decode(_ address: String) -> Data? {
        guard let decoded = Base58.decodeNoCheck(string: address) else {
            return nil
        }

        // Simple prefix (1 byte) + 32 byte key + 2 byte checksum = 35 bytes
        // Full prefix (2 bytes) + 32 byte key + 2 byte checksum = 36 bytes
        if decoded.count == 35 {
            // Single byte prefix
            return Data(decoded[1..<33])
        } else if decoded.count == 36 {
            // Two byte prefix
            return Data(decoded[2..<34])
        }
        return nil
    }

    /// Encode raw public key bytes to SS58 address with given prefix
    static func ss58Encode(publicKey: Data, prefix: UInt16) -> String {
        let ss58Prefix = "SS58PRE".data(using: .utf8)!

        var prefixBytes: Data
        if prefix < 64 {
            prefixBytes = Data([UInt8(prefix)])
        } else {
            // Two-byte encoding for prefix >= 64
            let first = UInt8(((prefix & 0xFC) >> 2) | 0x40)
            let second = UInt8((prefix >> 8) | ((prefix & 0x03) << 6))
            prefixBytes = Data([first, second])
        }

        let payload = prefixBytes + publicKey
        let checksumInput = ss58Prefix + payload
        let hash = Hash.blake2b(data: checksumInput, size: 64)
        let checksum = hash.prefix(2)

        return Base58.encodeNoCheck(data: payload + checksum)
    }

    /// Validate a Bittensor SS58 address (prefix 42)
    static func isValidAddress(_ address: String) -> Bool {
        guard let decoded = Base58.decodeNoCheck(string: address) else {
            return false
        }

        // Check minimum length: prefix(1-2) + pubkey(32) + checksum(2) = 35 or 36
        guard decoded.count >= 35 else { return false }

        let prefixByteCount: Int
        let decodedPrefix: UInt16

        if decoded[0] < 64 {
            prefixByteCount = 1
            decodedPrefix = UInt16(decoded[0])
        } else {
            guard decoded.count >= 36 else { return false }
            prefixByteCount = 2
            let first = decoded[0]
            let second = decoded[1]
            decodedPrefix = UInt16((first & 0x3F) << 2) | UInt16(second >> 6) | (UInt16(second & 0x3F) << 8)
        }

        guard decodedPrefix == ss58Prefix else { return false }

        let pubkey = Data(decoded[prefixByteCount..<(prefixByteCount + 32)])
        let checksum = Data(decoded[(prefixByteCount + 32)..<(prefixByteCount + 34)])

        // Verify checksum
        let ss58PrefixData = "SS58PRE".data(using: .utf8)!
        let payload = Data(decoded[0..<(prefixByteCount + 32)])
        let hash = Hash.blake2b(data: ss58PrefixData + payload, size: 64)

        return hash.prefix(2) == checksum && pubkey.count == 32
    }

    // MARK: - Pre-signed Image Hash (for MPC signing)

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let payload = try buildSigningPayload(keysignPayload: keysignPayload)

        // If payload > 256 bytes, hash with blake2b-256; otherwise sign directly
        let dataToSign: Data
        if payload.count > 256 {
            dataToSign = Hash.blake2b(data: payload, size: 32)
        } else {
            dataToSign = payload
        }

        return [dataToSign.hexString]
    }

    // MARK: - Signed Transaction Assembly

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        let signingPayload = try buildSigningPayload(keysignPayload: keysignPayload)

        // If payload > 256 bytes, hash with blake2b-256; otherwise sign directly
        let dataToSign: Data
        if signingPayload.count > 256 {
            dataToSign = Hash.blake2b(data: signingPayload, size: 32)
        } else {
            dataToSign = signingPayload
        }

        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: dataToSign)
        guard publicKey.verify(signature: signature, message: dataToSign) else {
            throw HelperError.runtimeError("fail to verify signature")
        }

        // Build the signed extensions (same as what goes before callData in the extrinsic)
        let signedExtra = try buildSignedExtra(keysignPayload: keysignPayload)
        let callData = try buildCallData(keysignPayload: keysignPayload)

        // Assemble the full extrinsic
        let extrinsic = assembleExtrinsic(
            signerPublicKey: pubkeyData,
            signature: signature,
            signedExtra: signedExtra,
            callData: callData
        )

        let transactionHash = Hash.blake2b(data: extrinsic, size: 32).toHexString()
        return SignedTransactionResult(
            rawTransaction: extrinsic.hexString,
            transactionHash: transactionHash
        )
    }

    // MARK: - Internal Building Blocks

    /// Build the call data: [moduleIndex, methodIndex] ++ MultiAddress::Id(0x00) ++ dest_pubkey(32B) ++ compact(amount)
    private static func buildCallData(keysignPayload: KeysignPayload) throws -> Data {
        guard let destPubkey = ss58Decode(keysignPayload.toAddress) else {
            throw HelperError.runtimeError("Invalid Bittensor destination address")
        }

        var data = Data()
        data.append(moduleIndex) // Balances pallet
        data.append(methodIndex) // transfer_allow_death
        data.append(0x00) // MultiAddress::Id variant
        data.append(destPubkey) // 32 bytes destination public key
        data.append(compactEncode(keysignPayload.toAmount)) // compact encoded amount

        return data
    }

    /// Build signed extra: mortal_era(2B) ++ compact(nonce) ++ compact(tip=0) ++ 0x00(CheckMetadataHash:Disabled)
    private static func buildSignedExtra(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Polkadot(
            _,
            let nonce,
            let currentBlockNumber,
            _, _, _, _
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("Missing Bittensor chain specific data")
        }

        var data = Data()
        data.append(encodeMortalEra(blockNumber: UInt64(currentBlockNumber), period: 64))
        data.append(compactEncode(nonce))
        data.append(compactEncode(UInt64(0))) // tip = 0
        data.append(0x00) // CheckMetadataHash: Disabled

        return data
    }

    /// Build additional signed data: specVersion(u32le) ++ txVersion(u32le) ++ genesisHash(32B) ++ blockHash(32B) ++ 0x00(CheckMetadataHash mode)
    private static func buildAdditionalSigned(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Polkadot(
            let recentBlockHash,
            _,
            _,
            let specVersion,
            let transactionVersion,
            let genesisHash,
            _
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("Missing Bittensor chain specific data")
        }

        var data = Data()

        // specVersion as u32 little-endian (explicit LE encoding)
        withUnsafeBytes(of: specVersion.littleEndian) { data.append(contentsOf: $0) }

        // transactionVersion as u32 little-endian (explicit LE encoding)
        withUnsafeBytes(of: transactionVersion.littleEndian) { data.append(contentsOf: $0) }

        // genesisHash (32 bytes)
        guard let genesisData = Data(hexString: genesisHash), genesisData.count == 32 else {
            throw HelperError.runtimeError("Invalid genesis hash")
        }
        data.append(genesisData)

        // blockHash (32 bytes)
        guard let blockHashData = Data(hexString: recentBlockHash), blockHashData.count == 32 else {
            throw HelperError.runtimeError("Invalid block hash")
        }
        data.append(blockHashData)

        // CheckMetadataHash: mode = 0x00 (Disabled)
        data.append(0x00)

        return data
    }

    /// Build the full signing payload: callData ++ signedExtra ++ additionalSigned
    private static func buildSigningPayload(keysignPayload: KeysignPayload) throws -> Data {
        let callData = try buildCallData(keysignPayload: keysignPayload)
        let signedExtra = try buildSignedExtra(keysignPayload: keysignPayload)
        let additionalSigned = try buildAdditionalSigned(keysignPayload: keysignPayload)

        return callData + signedExtra + additionalSigned
    }

    /// Assemble the final extrinsic:
    /// compactLen ++ 0x84 ++ 0x00(MultiAddr::Id) ++ signer(32B) ++ 0x00(MultiSig::Ed25519) ++ sig(64B) ++ signedExtra ++ callData
    private static func assembleExtrinsic(
        signerPublicKey: Data,
        signature: Data,
        signedExtra: Data,
        callData: Data
    ) -> Data {
        // Build the inner extrinsic (without length prefix)
        var inner = Data()
        inner.append(0x84) // Signed extrinsic version (0x80 | 0x04)
        inner.append(0x00) // MultiAddress::Id
        inner.append(signerPublicKey) // 32 bytes signer public key
        inner.append(0x00) // MultiSignature::Ed25519
        inner.append(signature) // 64 bytes signature
        inner.append(signedExtra) // era + nonce + tip + CheckMetadataHash
        inner.append(callData) // call data

        // Prepend compact length
        let lengthPrefix = compactLength(inner.count)
        return lengthPrefix + inner
    }
}
