//
//  TonJettonAddress.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// One spelling of a TON address, so every jetton lookup keyed by master
/// address agrees on what the key is.
///
/// The same contract reaches us three ways: Toncenter answers in raw
/// upper-case `0:HEX`, Tonkeeper's `ton-assets` lists raw lower-case, and
/// `TokensStore` / `Coin.contractAddress` hold the user-friendly `EQ…` form.
/// User-friendly bounceable is the canonical one here because it is the form
/// `CoinMeta.uniqueId` already dedups on — a discovered jetton has to collide
/// with a coin the vault holds — and because WalletCore offers no raw
/// converter, only `toUserFriendly`, which accepts either input spelling.
enum TonJettonAddress {

    /// The canonical key for `address`, or `nil` when it is not a TON address.
    /// Callers drop what does not canonicalise rather than falling back to the
    /// raw string: two spellings of one contract must never index separately.
    static func canonical(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TONAddressConverter.toUserFriendly(
            address: trimmed,
            bounceable: true,
            testnet: false
        )
    }
}
