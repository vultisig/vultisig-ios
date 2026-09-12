//
//  TonJettonRegistry.swift
//  VultisigApp
//

import Foundation

/// A jetton we treat as legitimate, keyed by its canonical master address.
struct VerifiedJetton: Equatable, Sendable {
    /// Canonical master address (see `TonJettonAddress`).
    let address: String
    let symbol: String
    let name: String?
    let decimals: Int?
    let logo: String?
    let priceProviderId: String?
    /// `.curated` for a bundled `TokensStore` entry, `.verified(source:)` for a
    /// whitelist one. Assigned by the builder from where the entry came, never
    /// decoded from the payload.
    let verification: TokenVerification
}

extension VerifiedJetton {
    /// A bundled TON jetton. Returns `nil` for the native coin and for anything
    /// whose contract address does not canonicalise.
    init?(curated meta: CoinMeta) {
        guard !meta.isNativeToken, let address = TonJettonAddress.canonical(meta.contractAddress) else {
            return nil
        }
        self.init(
            address: address,
            symbol: meta.ticker,
            name: nil,
            decimals: meta.decimals,
            logo: meta.logo.trimmedNonEmpty,
            priceProviderId: meta.priceProviderId.trimmedNonEmpty,
            verification: .curated
        )
    }

    /// A `ton-assets` entry. An entry with no usable symbol is dropped: it could
    /// neither be displayed nor contribute an impersonation skeleton.
    init?(whitelisted entry: TonAssetsJetton) {
        guard let address = TonJettonAddress.canonical(entry.address),
              let symbol = entry.symbol?.trimmedNonEmpty else {
            return nil
        }
        self.init(
            address: address,
            symbol: symbol,
            name: entry.name?.trimmedNonEmpty,
            decimals: entry.decimals,
            logo: entry.image?.trimmedNonEmpty,
            priceProviderId: entry.coingecko?.trimmedNonEmpty,
            verification: .verified(source: TonJettonRegistry.tonAssetsSource)
        )
    }
}

/// The jettons we consider legitimate, indexed for the two questions
/// classification asks: "is this address listed?" and "does this symbol or name
/// belong to a listed jetton?".
struct TonJettonRegistry: Equatable, Sendable {
    /// Source label carried by whitelist-sourced entries.
    static let tonAssetsSource = "ton-assets"

    static let empty = TonJettonRegistry([])

    private let byAddress: [String: VerifiedJetton]
    private let symbolSkeletons: Set<String>
    private let nameSkeletons: Set<String>

    /// Indexes `jettons` in order. On an address collision the **earlier**
    /// entry's metadata is kept — curated is supplied first, so our ticker,
    /// decimals, logo and price id win — but every entry's symbol and name are
    /// indexed regardless.
    ///
    /// Both halves matter for real Tether. Our curated entry carries the ticker
    /// `USDT` and no name; only the whitelist duplicate of the same contract
    /// contributes `USD₮` and `Tether USD`. Keeping only the winner's labels
    /// would let a "Tether USD" impostor pass as merely unverified.
    init(_ jettons: [VerifiedJetton]) {
        var byAddress: [String: VerifiedJetton] = [:]
        var symbols: Set<String> = []
        var names: Set<String> = []

        for jetton in jettons {
            if byAddress[jetton.address] == nil {
                byAddress[jetton.address] = jetton
            }
            let symbol = TonJettonSymbol.normalize(jetton.symbol)
            if !symbol.isEmpty {
                symbols.insert(symbol)
            }
            if let name = jetton.name.map(TonJettonSymbol.normalize), !name.isEmpty {
                names.insert(name)
            }
        }

        self.byAddress = byAddress
        self.symbolSkeletons = symbols
        self.nameSkeletons = names
    }

    /// The listed jetton at `address`, in any spelling. `nil` means unlisted,
    /// which is the whole basis of the `scam` tier: a counterfeit is only
    /// distinguishable from the asset it copies by its address.
    func entry(for address: String) -> VerifiedJetton? {
        guard let key = TonJettonAddress.canonical(address) else { return nil }
        return byAddress[key]
    }

    /// Whether `label` reads as a listed jetton's symbol or name. An empty
    /// skeleton never matches — a jetton whose symbol carries no Latin letters
    /// would otherwise impersonate whatever it collapsed onto.
    func impersonates(_ label: String?) -> Bool {
        guard let label else { return false }
        let skeleton = TonJettonSymbol.normalize(label)
        guard !skeleton.isEmpty else { return false }
        return symbolSkeletons.contains(skeleton) || nameSkeletons.contains(skeleton)
    }

    var count: Int { byAddress.count }
}
