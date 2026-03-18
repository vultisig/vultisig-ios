//
//  Wallet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import WalletCore
import CryptoKit

extension HDWallet {
    /// Return BIP32 master chain code (hex) for a mnemonic via WalletCore's HDWallet seed.
    func rootChainCodeHex() -> String {
        let seed = self.seed // 64 bytes BIP39 seed
        let key = SymmetricKey(data: "Bitcoin seed".data(using: .utf8)!)
        let mac = HMAC<SHA512>.authenticationCode(for: seed, using: key)
        let master = Data(mac) // 64 bytes: [master key (32) | chain code (32)]
        let chainCode = master.subdata(in: 32..<64)
        return chainCode.hexString
    }
}
