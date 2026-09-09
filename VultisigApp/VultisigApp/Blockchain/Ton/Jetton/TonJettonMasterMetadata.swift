//
//  TonJettonMasterMetadata.swift
//  VultisigApp
//

import Foundation

/// What Toncenter's indexer knows about a jetton master, with nothing
/// guaranteed: an unindexed or broken jetton can lack every field.
struct TonJettonMasterMetadata: Equatable, Sendable {
    /// Canonical master address (see `TonJettonAddress`).
    let address: String
    let symbol: String?
    let name: String?
    let decimals: Int?
    let logo: String?
    /// Toncenter's own scam flag. Honoured, but it carries almost nothing on its
    /// own — a sample of 40 jettons blacklisted elsewhere all reported `false`,
    /// which is why the registry and the impersonation check do the work.
    let isFlaggedScam: Bool?
}

extension TonJettonMasterMetadata {

    /// Indexes a Toncenter `metadata` map by canonical master address.
    ///
    /// The map is keyed by raw address and carries an entry for **every**
    /// address in the response — including each of the owner's jetton *wallets*,
    /// under `type: "jetton_wallets"` and also marked `valid: true`. Selecting
    /// on `valid` alone would therefore pick a wallet entry, which has no symbol
    /// or name, and every jetton would classify as unverified. The `type` filter
    /// is what makes the metadata usable at all.
    static func index(from metadata: [String: JettonMasterMetadata]?) -> [String: TonJettonMasterMetadata] {
        guard let metadata else { return [:] }

        var index: [String: TonJettonMasterMetadata] = [:]
        for (rawAddress, entry) in metadata {
            guard let address = TonJettonAddress.canonical(rawAddress),
                  let info = entry.masterTokenInfo else {
                continue
            }
            index[address] = TonJettonMasterMetadata(rawAddress: address, info: info)
        }
        return index
    }

    private init(rawAddress: String, info: JettonTokenInfo) {
        self.address = rawAddress
        self.symbol = info.symbol?.trimmedNonEmpty
        self.name = info.name?.trimmedNonEmpty
        self.decimals = info.extra?.decimals.flatMap { Int($0) }
        // Toncenter's imgproxy variants are normalized and served with
        // permissive CORS headers; the original `image` often is not.
        self.logo = info.extra?.imageMedium?.trimmedNonEmpty
            ?? info.extra?.imageSmall?.trimmedNonEmpty
            ?? info.extra?.imageBig?.trimmedNonEmpty
            ?? info.image?.trimmedNonEmpty
        self.isFlaggedScam = info.is_scam
    }
}

extension JettonMasterMetadata {
    /// The validated *master* entry, if this address has one. See
    /// `TonJettonMasterMetadata.index(from:)` for why `type` is filtered.
    ///
    /// A typed master entry always wins. An untyped one is accepted only when
    /// there is no typed master to be had, so that a Toncenter version which
    /// stopped emitting `type` degrades to reading the entry rather than to
    /// finding no metadata at all — which would classify every jetton on the
    /// chain as unverified and quietly stop discovery.
    var masterTokenInfo: JettonTokenInfo? {
        guard let entries = token_info else { return nil }
        return entries.first { $0.valid == true && $0.type == "jetton_masters" }
            ?? entries.first { $0.valid == true && $0.type == nil }
    }
}
