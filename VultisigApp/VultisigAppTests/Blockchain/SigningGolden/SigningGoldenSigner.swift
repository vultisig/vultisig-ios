//
//  SigningGoldenSigner.swift
//  VultisigAppTests
//
//  Deterministic signature synthesis for the signing golden-vector harness.
//
//  A real keysign gets its `[String: TssKeysignResponse]` from the TSS
//  ceremony. Here we synthesize the SAME map deterministically by signing each
//  pre-image hash with a FIXED test key whose public key is the coin's
//  `hexPublicKey` — so `TransactionCompiler.compileWithSignatures` (which
//  verifies the signature against the public key for most chains) accepts them
//  and the signed bytes are reproducible across runs.
//
//  The response-field encoding mirrors production exactly (see
//  `TssKeysignResponse` accessors in `Core/Extensions/TssExtension.swift`):
//    - ECDSA `getSignatureWithRecoveryID()` reads big-endian `r`/`s` + `recoveryID`.
//    - UTXO `getDERSignature()` reads the `derSignature` hex verbatim.
//    - EdDSA `getSignature()` reads big-endian `r`/`s`, left-pads, reverses to LE.
//  We populate every field an ECDSA response could be read through, so the same
//  synthesized response works whether a chain reads DER or (r,s,v).
//

import Foundation
import Tss
import WalletCore
@testable import VultisigApp

/// Which curve a vector's fixed key + signatures use.
enum SigningGoldenCurve {
    case secp256k1
    case ed25519
}

enum SigningGoldenSigner {

    /// Fixed secp256k1 test key (WalletCore's canonical test private key). Its
    /// compressed public key is used as `coin.hexPublicKey` for every ECDSA
    /// vector, so synthesized signatures verify.
    static let secp256k1KeyHex = "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63"

    /// Fixed ed25519 test key (same seed; a distinct key object per curve).
    static let ed25519KeyHex = "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63"

    static func privateKey(for curve: SigningGoldenCurve) -> PrivateKey {
        let hex = curve == .secp256k1 ? secp256k1KeyHex : ed25519KeyHex
        guard let data = Data(hexString: hex), let key = PrivateKey(data: data) else {
            fatalError("SigningGoldenSigner: invalid fixed test key")
        }
        return key
    }

    /// The public key that must be set as `coin.hexPublicKey` for a vector so
    /// synthesized signatures verify. secp256k1 is compressed (33 bytes).
    static func publicKeyHex(for curve: SigningGoldenCurve) -> String {
        let key = privateKey(for: curve)
        switch curve {
        case .secp256k1:
            return key.getPublicKeySecp256k1(compressed: true).data.hexString
        case .ed25519:
            return key.getPublicKeyEd25519().data.hexString
        }
    }

    /// Synthesize the TSS response map for a set of pre-image hashes, signing
    /// each with the fixed key for `curve`.
    static func signatures(
        forImageHashes hashes: [String],
        curve: SigningGoldenCurve
    ) throws -> [String: TssKeysignResponse] {
        let key = privateKey(for: curve)
        var result: [String: TssKeysignResponse] = [:]
        for hash in hashes {
            guard let digest = Data(hexString: hash) else {
                throw SignerError.badHash(hash)
            }
            let response = TssKeysignResponse()
            response.msg = hash
            switch curve {
            case .secp256k1:
                guard let signature = key.sign(digest: digest, curve: .secp256k1) else {
                    throw SignerError.signingFailed(hash)
                }
                // WalletCore returns 65 bytes: r(32, big-endian) ‖ s(32) ‖ recid(1).
                let r = signature.prefix(32)
                let s = signature.subdata(in: 32..<64)
                let recid = signature[64]
                response.r = r.hexString
                response.s = s.hexString
                response.recoveryID = String(format: "%02x", recid)
                // Reuse the production canonical-DER encoder so the UTXO path's
                // `getDERSignature()` reads exactly what a real ceremony would.
                response.derSignature = encodeCanonicalDERSignature(
                    r: [UInt8](r),
                    s: [UInt8](s)
                ).hexString
            case .ed25519:
                guard let signature = key.sign(digest: digest, curve: .ed25519) else {
                    throw SignerError.signingFailed(hash)
                }
                // Ed25519 signature is R(32, little-endian) ‖ S(32). Store the
                // big-endian halves so production's `getSignature()` reverses
                // them back to LE (mirrors SchnorrKeysign / SolanaHelperTests).
                response.r = Data(signature.prefix(32).reversed()).hexString
                response.s = Data(signature.suffix(32).reversed()).hexString
            }
            result[hash] = response
        }
        return result
    }

    enum SignerError: Error {
        case badHash(String)
        case signingFailed(String)
    }
}
