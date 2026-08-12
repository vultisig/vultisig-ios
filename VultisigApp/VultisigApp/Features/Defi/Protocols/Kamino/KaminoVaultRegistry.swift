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

/// A curated vault the app offers.
///
/// This carries everything a transaction is checked against, because a value
/// fetched from the API cannot be used to validate a transaction built by the
/// same API — the check would be circular, and a compromised response could
/// supply a matching pair. The fields below are all immutable properties of the
/// vault: a kVault's mints, their decimals and its farm are fixed at creation.
/// Everything that legitimately moves — name, minimums, APY, rates, the lookup
/// table — stays live, and `KaminoService` refuses a response that disagrees
/// with the pinned identity.
struct KaminoVaultDescriptor: Hashable, Identifiable {
    let address: String
    /// The vault's underlying token mint. Pinned: the deposit source and the
    /// withdraw destination are derived from it.
    let tokenMint: String
    /// Pinned because it scales every amount. A wrong scale mis-sizes the
    /// transfer by a power of ten while every other check still passes.
    let tokenDecimals: Int
    let sharesMint: String
    let sharesDecimals: Int
    /// The farm a deposit stakes into, or `nil` when the vault has none. Pinned
    /// because `farms::stake` moves the whole share balance into it.
    let farm: String?
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

    /// The chain the curated vaults live on. kVaults are Solana-only, and
    /// callers gate on this rather than on `.solana` literals so a Kamino read
    /// or write can never fire while the user is on another chain's DeFi tab.
    static let chain: Chain = .solana

    /// The kVaults program every deposit and withdraw invokes.
    static let programId = "KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd"

    /// Kamino's farms program. Every launch vault has a farm attached, so a
    /// deposit ends with `initializeUser` + `stake` against this program and the
    /// shares never land in the user's wallet.
    static let farmsProgramId = "FarmsPZpWu9i7Kky8tPN37rs2TpmMrAZrC7S7vJa91Hr"

    /// Wrapped SOL. The SOL vault's underlying token is this mint, not native
    /// SOL, which is why its deposits carry a wrap prefix.
    static let wrappedSolMint = "So11111111111111111111111111111111111111112"

    /// Circle's USDC — the underlying token of both dollar vaults.
    static let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    static let steakhouseUSDC = KaminoVaultDescriptor(
        address: "HDsayqAsDWy3QvANGqh2yNraqcD8Fnjgh73Mhb3WRS5E",
        tokenMint: usdcMint,
        tokenDecimals: 6,
        sharesMint: "7D8C5pDFxug58L9zkwK7bCiDg4kD4AygzbcZUmf5usHS",
        sharesDecimals: 6,
        farm: "9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj",
        fallbackName: "Steakhouse USDC",
        curator: "Steakhouse Financial",
        riskTier: .conservative
    )

    static let rwaUSDC = KaminoVaultDescriptor(
        address: "DWSXb18xZApz29vnQpgR2m6MynCT7PznaXt7Ut7M7KaP",
        tokenMint: usdcMint,
        tokenDecimals: 6,
        sharesMint: "DgHN3q3dSYAchNX7V3D4aYiTWMx8RHTgHbfPiwiqBkE9",
        sharesDecimals: 6,
        farm: "ArwyAHmnFmbKbUxC2fnK5VUEpspHrnoFtJ22bvEyriKk",
        fallbackName: "RWA USDC",
        curator: "RockawayX",
        riskTier: .privateCredit
    )

    /// The share scale differs from the token scale here — 9 against 6. Nothing
    /// may assume the two match.
    static let allezSOL = KaminoVaultDescriptor(
        address: "A1so1bPD3W1TfeFwboDh8yfAAVaVtcdAYBYCjhg2mJQ",
        tokenMint: wrappedSolMint,
        tokenDecimals: 9,
        sharesMint: "FiM4VQdXXnTXL7GgChryf9zHNG9cmvKECwf34L2y3CkN",
        sharesDecimals: 6,
        farm: "H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh",
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

extension KaminoRiskTier {
    var title: String {
        switch self {
        case .conservative:
            "kaminoEarnRiskConservative".localized
        case .privateCredit:
            "kaminoEarnRiskPrivateCredit".localized
        }
    }
}

extension KaminoVaultDescriptor {
    /// The wallet coin the vault's underlying token corresponds to — the logo,
    /// ticker and price feed a position is displayed and valued with.
    ///
    /// The SOL vault's underlying token is *wrapped* SOL, which the token store
    /// does not carry: wrapping is a 1:1 escrow of the native coin and the two
    /// share a price, so it resolves to native SOL. Everything else is looked up
    /// by mint, and a mint with no entry yields `nil` — a position with no
    /// resolvable coin is left out of the fiat roll-up rather than valued at an
    /// arbitrary rate.
    var underlyingCoinMeta: CoinMeta? {
        guard tokenMint != KaminoVaultRegistry.wrappedSolMint else {
            return DefiPositionsService.nativeSolanaMeta
        }
        return TokensStore.findTokenMeta(chain: .solana, contractAddress: tokenMint)
    }
}
