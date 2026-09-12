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

    /// Balances pallet module index. Verified against subtensor's own
    /// `construct_runtime!` (`runtime/src/lib.rs`: `Balances: pallet_balances = 5`).
    static let moduleIndex: UInt8 = 5

    /// `pallet_balances` call indices, verified against the exact
    /// `pallet-balances` revision subtensor's `runtime/Cargo.toml` pins
    /// (`RaoFoundation/polkadot-sdk` @ `cacb4310f20c7cac83eb3ccd8ed5a5ad4212608a`,
    /// `substrate/frame/balances/src/lib.rs`), which declares both calls with
    /// explicit `#[pallet::call_index(_)]` attributes rather than relying on
    /// declaration order.
    static let transferAllowDeathIndex: UInt8 = 0
    static let transferKeepAliveIndex: UInt8 = 3

    /// Subtensor's existential deposit (`runtime/src/lib.rs`:
    /// `pub const EXISTENTIAL_DEPOSIT: u64 = 500`). An account whose free
    /// balance falls below this is reaped by the runtime.
    static let existentialDeposit: BigInt = 500

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

    /// Decode an SS58 address to its raw public key bytes (32 bytes for ed25519),
    /// requiring an exact prefix + checksum match. This is the single decode
    /// both the form (`isValidAddress`) and the sign path (`buildCallData`)
    /// use, so they can never accept different addresses.
    static func ss58Decode(_ address: String) -> Data? {
        AnyAddress(string: address, coin: .polkadot, ss58Prefix: UInt32(ss58Prefix))?.data
    }

    /// Encode raw public key bytes to a Bittensor SS58 (prefix 42) address.
    static func ss58Encode(publicKey: Data) -> String {
        guard let key = PublicKey(data: publicKey, type: .ed25519) else {
            return ""
        }
        return AnyAddress(publicKey: key, coin: .polkadot, ss58Prefix: UInt32(ss58Prefix)).description
    }

    /// Validate a Bittensor SS58 address (prefix 42). Thin wrapper over
    /// `ss58Decode` so the form can never accept an address the sign path
    /// would reject, or vice versa.
    static func isValidAddress(_ address: String) -> Bool {
        AnyAddress.isValidSS58(string: address, coin: .polkadot, ss58Prefix: UInt32(ss58Prefix))
    }

    /// The Substrate burn/zero AccountId (32 zero bytes) — SS58-42-encodes to
    /// `5C4hrfjw9DjXZTzV3MwzrrAr9P1MJhSrvWGWqi1eSuyUpnhM`, a syntactically
    /// valid Bittensor address with no known private key, so anything sent
    /// there is unspendable.
    private static let burnAccountId = Data(repeating: 0, count: 32)

    /// True when `address` SS58-decodes to the burn AccountId. The
    /// byte-level `assertNotBurnAccount` guard in `buildCallData` is the
    /// one that does not depend on how strict `ss58Decode` is — this
    /// string-level check is only ever reached from the form, after
    /// `isValidAddress` has already required a well-formed address.
    static func isBurnAddress(_ address: String) -> Bool {
        ss58Decode(address) == burnAccountId
    }

    // MARK: - Account Storage Parsing

    /// A read of the `System.Account` storage for one address, distinguishing
    /// a confirmed balance (including a legitimate zero for an account with
    /// no ledger entry) from a read that couldn't be determined. Callers that
    /// treat "no evidence" as reason to block something (the destination-ED
    /// guard) must fail open on `.unknown`, never read it as `.confirmed(.zero)`.
    enum AccountStorageRead: Equatable {
        case confirmed(BigInt)
        case unknown
    }

    /// Pure interpretation of a `state_getStorage` result for the
    /// `System.Account` key — no network access, so the malformed/truncated/
    /// absent-account cases can be pinned directly without mocking the RPC
    /// layer.
    ///
    /// `nil` means the caller determined the storage key doesn't exist in
    /// the trie (Substrate's JSON-null sentinel) — the account has no ledger
    /// entry, which IS a confirmed zero balance. An actual empty STRING is
    /// NOT that sentinel — a well-formed node never returns one for this
    /// call — so it's unknown, not zero. A non-empty response shorter than
    /// the `AccountInfo` layout requires, or one whose free-balance field
    /// fails to parse, is likewise a malformed/truncated read, not a
    /// confirmed value, and must not be treated as zero.
    static func interpretAccountStorage(_ rawResult: String?) -> AccountStorageRead {
        guard let result = rawResult else {
            // Substrate's sentinel for "no value" is JSON null, which the
            // caller maps to `nil` here — the account has no ledger entry,
            // which IS a confirmed zero balance.
            return .confirmed(.zero)
        }
        guard !result.isEmpty else {
            // An actual empty STRING is not that sentinel — a well-formed
            // node never returns one for this call. Unknown, not zero.
            return .unknown
        }

        // Parse SCALE-encoded AccountInfo: nonce(4) + consumers(4) + providers(4) + sufficients(4) + free(16) + ...
        let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard hex.count >= 64, hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else {
            return .unknown
        }

        // free balance at bytes 16-31 (hex chars 32-63), u128 little-endian
        let freeHex = String(hex[hex.index(hex.startIndex, offsetBy: 32)..<hex.index(hex.startIndex, offsetBy: 64)])
        // Reverse byte pairs for LE → BE conversion
        var beHex = ""
        for i in stride(from: freeHex.count - 2, through: 0, by: -2) {
            let start = freeHex.index(freeHex.startIndex, offsetBy: i)
            let end = freeHex.index(start, offsetBy: 2)
            beHex += String(freeHex[start..<end])
        }

        guard let balance = BigInt(beHex, radix: 16) else {
            // Malformed hex in the free-balance field is not a confirmed
            // zero — the whole point of this type is to not let a parse
            // failure masquerade as a real value.
            return .unknown
        }
        return .confirmed(balance)
    }

    // MARK: - Pre-signed Image Hash (for MPC signing)

    /// `keepAlive` selects the Balances call: `transfer_keep_alive` (default)
    /// fails on-chain rather than reap the sender, while `transfer_allow_death`
    /// permits draining the account to zero. No caller passes `false` today —
    /// there is no UI affordance for a user to explicitly empty a TAO account —
    /// so this parameter exists to keep both calls available to a future
    /// reap-confirmation flow without a second signature path. Every existing
    /// send defaults to keep-alive.
    static func getPreSignedImageHash(keysignPayload: KeysignPayload, keepAlive: Bool = true) throws -> [String] {
        let payload = try buildSigningPayload(keysignPayload: keysignPayload, keepAlive: keepAlive)

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
                                     signatures: [String: TssKeysignResponse],
                                     keepAlive: Bool = true) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        let signingPayload = try buildSigningPayload(keysignPayload: keysignPayload, keepAlive: keepAlive)

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
        let callData = try buildCallData(keysignPayload: keysignPayload, keepAlive: keepAlive)

        // Assemble the full extrinsic
        let extrinsic = assembleExtrinsic(
            signerPublicKey: pubkeyData,
            signature: signature,
            signedExtra: signedExtra,
            callData: callData
        )

        // Prefix with `0x` to match the hash the node returns from
        // `author_submitExtrinsic`, so the locally computed hash stays
        // consistent whichever device broadcasts (vs. gets the duplicate).
        let transactionHash = "0x" + Hash.blake2b(data: extrinsic, size: 32).toHexString()
        return SignedTransactionResult(
            rawTransaction: extrinsic.hexString,
            transactionHash: transactionHash
        )
    }

    // MARK: - Internal Building Blocks

    /// Build the call data: [moduleIndex, methodIndex] ++ MultiAddress::Id(0x00) ++ dest_pubkey(32B) ++ compact(amount)
    private static func buildCallData(keysignPayload: KeysignPayload, keepAlive: Bool) throws -> Data {
        guard let destPubkey = ss58Decode(keysignPayload.toAddress) else {
            throw HelperError.runtimeError("Invalid Bittensor destination address")
        }
        try assertNotBurnAccount(destPubkey)

        var data = Data()
        data.append(moduleIndex) // Balances pallet
        data.append(keepAlive ? transferKeepAliveIndex : transferAllowDeathIndex)
        data.append(0x00) // MultiAddress::Id variant
        data.append(destPubkey) // 32 bytes destination public key
        data.append(compactEncode(keysignPayload.toAmount)) // compact encoded amount

        return data
    }

    /// Fail-closed guard so a keysign payload never builds a call to the burn
    /// AccountId even if it bypassed this device's send-form validation — a
    /// co-signer that only sees the payload at keysign time still routes
    /// through here before anything gets signed.
    private static func assertNotBurnAccount(_ pubkey: Data) throws {
        guard pubkey != burnAccountId else {
            throw HelperError.runtimeError("Bittensor destination is the burn/zero account")
        }
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
    private static func buildSigningPayload(keysignPayload: KeysignPayload, keepAlive: Bool) throws -> Data {
        let callData = try buildCallData(keysignPayload: keysignPayload, keepAlive: keepAlive)
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
