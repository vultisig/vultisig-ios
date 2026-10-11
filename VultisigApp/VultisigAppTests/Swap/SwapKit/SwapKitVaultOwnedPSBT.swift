//
//  SwapKitVaultOwnedPSBT.swift
//  VultisigAppTests
//
//  The captured SwapKit PSBTs pay from third-party addresses, so signing them
//  with the golden test key trips the ownership guard. These helpers rewrite
//  an input's prev-output script to the golden key's, keeping every other byte.
//

import Foundation
import WalletCore
@testable import VultisigApp

enum SwapKitVaultOwnedPSBT {

    static var goldenPubKeyHex: String {
        SigningGoldenSigner.publicKeyHex(for: .secp256k1)
    }

    static var goldenKeyHash: Data {
        let pubkey = Data(hexString: goldenPubKeyHex) ?? Data()
        return Hash.ripemd(data: Hash.sha256(data: pubkey))
    }

    static var goldenP2WPKHScript: Data { Data([0x00, 0x14]) + goldenKeyHash }

    static var goldenP2PKHScript: Data { Data([0x76, 0xa9, 0x14]) + goldenKeyHash + Data([0x88, 0xac]) }

    /// Replaces `script` with `replacement` — every occurrence, or only the
    /// first when `firstOnly` is set.
    static func replacing(
        script: Data,
        with replacement: Data,
        in psbt: Data,
        firstOnly: Bool = false
    ) -> Data {
        precondition(script.count == replacement.count)
        var bytes = psbt
        var searchStart = bytes.startIndex
        while let range = bytes.range(of: script, in: searchStart..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: replacement)
            if firstOnly { break }
            searchStart = range.upperBound
        }
        return bytes
    }
}
