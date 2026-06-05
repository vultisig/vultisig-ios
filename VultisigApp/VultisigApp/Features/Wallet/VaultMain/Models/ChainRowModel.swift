//
//  ChainRowModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/06/2026.
//

import Foundation

/// Value-type projection of a chain's wallet row, precomputed once in
/// `VaultDetailViewModel` instead of derived per-row from the live `Vault`/`Coin`
/// SwiftData models. Driving the list off this snapshot makes membership the
/// reactive source (a `@Published [ChainRowModel]`) and keeps rows cheap and
/// `Equatable`, so SwiftUI can skip unchanged rows while scrolling.
struct ChainRowModel: Identifiable, Equatable {
    let chain: Chain
    /// Native coin ticker (e.g. "ETH" for Base/Arbitrum/Optimism, "BTC" for
    /// Bitcoin). Distinct from `chain.ticker` (BASE/ARB/OP…); wallet search
    /// matches the asset ticker so "ETH" surfaces every ETH-based chain, the
    /// same as the pre-projection search did via the native coin's ticker.
    let nativeTicker: String
    /// Precomputed address for the copy affordance (native coin's, falling back
    /// to the first coin on the chain).
    let address: String
    /// Preformatted fiat balance, currency symbol included.
    let fiatBalance: String
    /// Native coin balance with ticker (e.g. "0.5 BTC").
    let cryptoBalance: String
    /// Number of coins on the chain — drives the "N assets" subtitle.
    let assetCount: Int

    var id: Chain { chain }
}
