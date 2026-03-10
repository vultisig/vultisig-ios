//
//  CoinFactory+QBTC.swift
//  VultisigApp
//

import Foundation
import WalletCore
import CryptoSwift

extension CoinFactory {

    /// Creates a Coin for QBTC chain using ML-DSA-44 public key
    static func createMLDSACoin(asset: CoinMeta, publicKeyMLDSA44: String) throws -> Coin {
        let address = try generateQBTCAddress(publicKeyMLDSA44: publicKeyMLDSA44)
        return Coin(asset: asset, address: address, hexPublicKey: publicKeyMLDSA44)
    }

    /// Generates a QBTC address from an ML-DSA-44 public key
    /// Derivation: "bqs" + Base58([0x00] + SHA3-256(pubkey)[0..20] + SHA3-256(versioned)[0..4])
    static func generateQBTCAddress(publicKeyMLDSA44: String) throws -> String {
        guard let pubKeyData = Data(hexString: publicKeyMLDSA44), !pubKeyData.isEmpty else {
            throw Errors.invalidPublicKey(pubKey: "MLDSA public key is invalid: \(publicKeyMLDSA44)")
        }

        // Step 1: SHA3-256 hash of the public key
        let sha3Hash = pubKeyData.sha3(.sha256)

        // Step 2: Version byte 0x00 + first 20 bytes of hash
        var versioned = Data([0x00])
        versioned.append(sha3Hash.prefix(20))

        // Step 3: Checksum = first 4 bytes of SHA3-256(versioned)
        let checksumHash = versioned.sha3(.sha256)
        let checksum = checksumHash.prefix(4)

        // Step 4: Base58 encode versioned + checksum, prepend "bqs"
        var addressBytes = versioned
        addressBytes.append(checksum)
        return "bqs" + Base58.encodeNoCheck(data: addressBytes)
    }
}
