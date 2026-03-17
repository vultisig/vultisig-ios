//
//  CoinFactory+QBTC.swift
//  VultisigApp
//

import Foundation
import WalletCore
import CryptoKit

extension CoinFactory {

    /// Creates a Coin for QBTC chain using ML-DSA-44 public key
    /// Address derivation: Bech32("qbtc", RIPEMD160(SHA256(mldsa_pubkey_bytes)))
    static func createMLDSACoin(asset: CoinMeta, publicKeyMLDSA44: String) throws -> Coin {
        let address = try generateQBTCAddress(publicKeyMLDSA44: publicKeyMLDSA44)
        return Coin(asset: asset, address: address, hexPublicKey: publicKeyMLDSA44)
    }

    /// Generates a QBTC Bech32 address from an ML-DSA-44 public key
    /// Follows Cosmos SDK address derivation: Bech32(hrp, RIPEMD160(SHA256(pubkey_bytes)))
    static func generateQBTCAddress(publicKeyMLDSA44: String) throws -> String {
        guard let pubKeyData = Data(hexString: publicKeyMLDSA44), !pubKeyData.isEmpty else {
            throw Errors.invalidPublicKey(pubKey: "MLDSA public key is invalid: \(publicKeyMLDSA44)")
        }

        // Step 1: SHA256 hash of the raw public key bytes
        let sha256Hash = Hash.sha256(data: pubKeyData)

        // Step 2: RIPEMD160 hash of the SHA256 result → 20-byte address
        let addressBytes = Hash.ripemd(data: sha256Hash)

        // Step 3: Bech32 encode with "qbtc" HRP
        return Bech32.encode(hrp: "qbtc", data: addressBytes)
    }
}
