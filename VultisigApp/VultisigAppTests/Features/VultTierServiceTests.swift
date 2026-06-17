//
//  VultTierServiceTests.swift
//  VultisigAppTests
//
//  Pins the discount-tier *basis* migration: tiers resolve from the staked sVULT
//  balance, not raw held VULT. Raw VULT stays reachable for buy-routing, and the
//  thresholds / bps mapping / Thorguard ladder are unchanged by the migration.
//

@testable import VultisigApp
import XCTest

@MainActor
final class VultTierServiceTests: XCTestCase {

    private let service = VultTierService()

    // MARK: - Token accessors are distinct (sVULT basis vs raw VULT routing)

    func test_getStakedVultToken_returnsSVULT_notRawVULT() {
        let vault = makeVault(stakedSVULT: 5_000, rawVULT: 12_345)

        let staked = service.getStakedVultToken(for: vault)
        XCTAssertEqual(staked?.ticker, "sVULT")
        XCTAssertEqual(staked?.balanceDecimal, 5_000)
    }

    func test_getVultToken_stillReturnsRawVULT_forBuyRouting() {
        // #4590 + the buy-VULT routing call sites depend on raw VULT staying
        // reachable; the migration must not repurpose `getVultToken`.
        let vault = makeVault(stakedSVULT: 5_000, rawVULT: 12_345)

        let raw = service.getVultToken(for: vault)
        XCTAssertEqual(raw?.ticker, "VULT")
        XCTAssertEqual(raw?.balanceDecimal, 12_345)
    }

    func test_accessors_resolveDifferentCoins() {
        let vault = makeVault(stakedSVULT: 1, rawVULT: 2)
        XCTAssertNotEqual(service.getStakedVultToken(for: vault), service.getVultToken(for: vault))
    }

    // MARK: - Tier resolves from the STAKED balance

    func test_cachedTier_resolvesFromStakedBalance_notRawVULT() async {
        // sVULT clears Diamond (mid-band, clear of the 100k/1M thresholds so the
        // 18-dp base-unit round-trip can't drift across a boundary); raw VULT is
        // empty. The tier must come from sVULT. Diamond is non-upgradeable, so no
        // Thorguard eth_call fires.
        let vault = makeVault(stakedSVULT: 250_000, rawVULT: 0)

        let tier = await service.fetchDiscountTier(for: vault, cached: true)

        XCTAssertEqual(tier, .diamond)
    }

    func test_cachedBasis_ignoresRawVULT_staleHeldValueCannotBleedIn() {
        // The migration's failure mode: a large *held* VULT balance must NOT feed
        // the tier basis once it's staked. The cached tier reads
        // `getStakedVultToken(...).balanceDecimal`, which is 0 here despite the
        // 1,000,000 raw VULT that previously would have unlocked Ultimate — and a
        // 0 basis maps to no tier. (Asserted at the balance accessor to keep the
        // case network-free; the nil-tier path would otherwise probe Thorguard.)
        let vault = makeVault(stakedSVULT: 0, rawVULT: 1_000_000)

        let basis = service.getStakedVultToken(for: vault)?.balanceDecimal ?? 0
        XCTAssertEqual(basis, 0)
        XCTAssertNil(tier(for: basis))
    }

    func test_cachedTier_resolvesUltimate_fromTopStakedBalance() async {
        // Clear of the 1M threshold so the base-unit round-trip can't drift below
        // it; Ultimate is non-upgradeable, so no Thorguard eth_call fires.
        let vault = makeVault(stakedSVULT: 2_000_000, rawVULT: 0)

        let tier = await service.fetchDiscountTier(for: vault, cached: true)

        XCTAssertEqual(tier, .ultimate)
    }

    // MARK: - Thresholds + bps mapping unchanged by the basis migration

    func test_thresholds_unchanged() {
        XCTAssertEqual(VultDiscountTier.bronze.balanceToUnlock, 1_500)
        XCTAssertEqual(VultDiscountTier.silver.balanceToUnlock, 3_000)
        XCTAssertEqual(VultDiscountTier.gold.balanceToUnlock, 7_500)
        XCTAssertEqual(VultDiscountTier.platinum.balanceToUnlock, 15_000)
        XCTAssertEqual(VultDiscountTier.diamond.balanceToUnlock, 100_000)
        XCTAssertEqual(VultDiscountTier.ultimate.balanceToUnlock, 1_000_000)
    }

    func test_bpsMapping_unchanged() {
        XCTAssertEqual(VultDiscountTier.bronze.bpsDiscount, 5)
        XCTAssertEqual(VultDiscountTier.silver.bpsDiscount, 10)
        XCTAssertEqual(VultDiscountTier.gold.bpsDiscount, 20)
        XCTAssertEqual(VultDiscountTier.platinum.bpsDiscount, 25)
        XCTAssertEqual(VultDiscountTier.diamond.bpsDiscount, 35)
        XCTAssertEqual(VultDiscountTier.ultimate.bpsDiscount, .max)
    }

    /// The balance→tier selection is the migration's only moving part; the
    /// expression itself (highest threshold a balance clears) is basis-agnostic
    /// and must be unchanged. Mirrors `fetchDiscountTier`'s mapping.
    func test_balanceToTierMapping_isUnchanged() {
        XCTAssertNil(tier(for: 0))
        XCTAssertNil(tier(for: 1_499))
        XCTAssertEqual(tier(for: 1_500), .bronze)
        XCTAssertEqual(tier(for: 2_999), .bronze)
        XCTAssertEqual(tier(for: 3_000), .silver)
        XCTAssertEqual(tier(for: 7_500), .gold)
        XCTAssertEqual(tier(for: 15_000), .platinum)
        XCTAssertEqual(tier(for: 99_999), .platinum)
        XCTAssertEqual(tier(for: 100_000), .diamond)
        XCTAssertEqual(tier(for: 1_000_000), .ultimate)
    }

    // MARK: - Thorguard NFT bump is left intact

    func test_thorguardContractAddress_unchanged() {
        // The Thorguard boost is a separate eth_call at its own address and must
        // not be touched by the staking-basis migration.
        XCTAssertEqual(
            service.thorguardContractAddress,
            "0xa98b29a8f5a247802149c268ecf860b8308b7291"
        )
    }

    // MARK: - Fixtures

    private func makeVault(stakedSVULT: Decimal, rawVULT: Decimal) -> Vault {
        let vault = Vault(
            name: "Tier Test Vault",
            signers: [],
            pubKeyECDSA: "tier-pub-ecdsa",
            pubKeyEdDSA: "tier-pub-eddsa-\(stakedSVULT)-\(rawVULT)",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        vault.coins = [
            ethCoin(ticker: "sVULT", balance: stakedSVULT),
            ethCoin(ticker: "VULT", balance: rawVULT)
        ]
        return vault
    }

    /// Builds an 18-decimal Ethereum ERC-20 coin carrying `balance` (whole units).
    private func ethCoin(ticker: String, balance: Decimal) -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: ticker,
            logo: "vult",
            decimals: 18,
            priceProviderId: "vultisig",
            contractAddress: "\(ticker)-contract",
            isNativeToken: false
        )
        let coin = Coin(asset: meta, address: "0xtest-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalanceString(for: balance, decimals: 18)
        return coin
    }

    /// `Decimal` whole units → base-unit string, matching `balanceDecimal`'s
    /// `rawBalance / 10^decimals`.
    private func rawBalanceString(for whole: Decimal, decimals: Int) -> String {
        let scaled = whole * pow(Decimal(10), decimals)
        return NSDecimalNumber(decimal: scaled).stringValue
    }

    /// The exact balance→tier selection `fetchDiscountTier` performs.
    private func tier(for balance: Decimal) -> VultDiscountTier? {
        VultDiscountTier.allCases
            .sorted { $0.balanceToUnlock > $1.balanceToUnlock }
            .first { balance >= $0.balanceToUnlock }
    }
}
