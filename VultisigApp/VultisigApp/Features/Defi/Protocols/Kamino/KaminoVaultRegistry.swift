//
//  KaminoVaultRegistry.swift
//  VultisigApp
//

import Foundation

/// Relative risk of a launch vault, used to order and label them.
///
/// This is curation, not API data — Kamino exposes no risk or curator field
/// anywhere, so both live here and travel with the allow-list.
enum KaminoRiskTier: Int, Hashable, CaseIterable {
    /// Plain over-collateralised lending against liquid crypto collateral.
    case conservative = 0
    /// Lending against tokenized private credit — reinsurance, receivables and
    /// corporate bonds. Materially different risk from the conservative tier and
    /// must not be presented as government-backed.
    case privateCredit = 1
}

/// A curated vault the app offers. The address is the allow-list; everything the
/// API can tell us (name, mints, decimals, minimums, APY) is fetched live, and
/// everything it cannot (curator, risk tier) is carried here.
struct KaminoVaultDescriptor: Hashable, Identifiable {
    let address: String
    /// Shown until live state arrives, and as the fallback if it never does.
    let fallbackName: String
    let curator: String
    let riskTier: KaminoRiskTier

    var id: String { address }
}

/// The curated set of Kamino Earn vaults the app exposes.
///
/// Kamino runs 166 vaults; `GET /kvaults/vaults` returns all of them as a single
/// 339 KB payload. The allow-list both curates and keeps the fetch small — the
/// three entries are hydrated with three ~2.8 KB per-vault requests instead.
enum KaminoVaultRegistry {

    /// The kVaults program every deposit and withdraw invokes.
    static let programId = "KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd"

    /// Kamino's farms program. Every launch vault has a farm attached, so a
    /// deposit ends with `initializeUser` + `stake` against this program and the
    /// shares never land in the user's wallet.
    static let farmsProgramId = "FarmsPZpWu9i7Kky8tPN37rs2TpmMrAZrC7S7vJa91Hr"

    static let steakhouseUSDC = KaminoVaultDescriptor(
        address: "HDsayqAsDWy3QvANGqh2yNraqcD8Fnjgh73Mhb3WRS5E",
        fallbackName: "Steakhouse USDC",
        curator: "Steakhouse Financial",
        riskTier: .conservative
    )

    static let rwaUSDC = KaminoVaultDescriptor(
        address: "DWSXb18xZApz29vnQpgR2m6MynCT7PznaXt7Ut7M7KaP",
        fallbackName: "RWA USDC",
        curator: "RockawayX",
        riskTier: .privateCredit
    )

    static let allezSOL = KaminoVaultDescriptor(
        address: "A1so1bPD3W1TfeFwboDh8yfAAVaVtcdAYBYCjhg2mJQ",
        fallbackName: "Allez SOL",
        curator: "Allez Labs",
        riskTier: .conservative
    )

    static let allowList: [KaminoVaultDescriptor] = [steakhouseUSDC, rwaUSDC, allezSOL]

    static func descriptor(for address: String) -> KaminoVaultDescriptor? {
        allowList.first { $0.address == address }
    }

    /// Whether an address is one the app is willing to transact against. Used to
    /// reject any vault a response mentions that we did not ask about.
    static func isAllowed(_ address: String) -> Bool {
        descriptor(for: address) != nil
    }
}
