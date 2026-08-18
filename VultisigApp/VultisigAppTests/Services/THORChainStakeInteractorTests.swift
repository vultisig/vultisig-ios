//
//  THORChainStakeInteractorTests.swift
//  VultisigAppTests
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class THORChainStakeInteractorTests: XCTestCase {

    // MARK: - scaledAmount

    func test_scaledAmount_stcyWithEightDecimals() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 344_000_000, decimals: 8)
        XCTAssertEqual(result, Decimal(string: "3.44"))
    }

    func test_scaledAmount_zeroRawAmount() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 0, decimals: 8)
        XCTAssertEqual(result, 0)
    }

    func test_scaledAmount_zeroDecimalsReturnsRawUnchanged() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 42, decimals: 0)
        XCTAssertEqual(result, 42)
    }

    func test_scaledAmount_largeRawAmount() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 100_000_000_000, decimals: 8)
        XCTAssertEqual(result, 1_000)
    }

    func test_scaledAmount_eighteenDecimals() {
        let rawAmount = Decimal(string: "1000000000000000000")!
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: 18)
        XCTAssertEqual(result, 1)
    }

    func test_scaledAmount_preservesSmallFractions() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 1, decimals: 8)
        XCTAssertEqual(result, Decimal(string: "0.00000001"))
    }

    // MARK: - APR fractionalRate

    /// Per the Rujira GraphQL schema, `Bigint` decimal scalars are scaled to 12 decimal places.
    /// `11623890337` should resolve to `0.011624` (≈ 1.16% when rendered as a percentage).
    func test_aprFractionalRate_scales12Decimals() throws {
        let apr = try decodeAPR(value: "11623890337", status: "AVAILABLE")
        let result = try XCTUnwrap(apr.fractionalRate)
        XCTAssertEqual(result, 0.011623890337, accuracy: 1e-12)
    }

    func test_aprFractionalRate_treatsMissingStatusAsAvailable() throws {
        // Backwards-compat: if the API ever omits `status`, fall back to using the value.
        let apr = try decodeAPR(value: "1000000000000", status: nil)
        let result = try XCTUnwrap(apr.fractionalRate)
        XCTAssertEqual(result, 1.0, accuracy: 1e-12)
    }

    func test_aprFractionalRate_returnsNilForNotApplicable() throws {
        let apr = try decodeAPR(value: "0", status: "NOT_APPLICABLE")
        XCTAssertNil(apr.fractionalRate)
    }

    func test_aprFractionalRate_returnsNilForSoon() throws {
        let apr = try decodeAPR(value: "0", status: "SOON")
        XCTAssertNil(apr.fractionalRate)
    }

    func test_aprFractionalRate_returnsNilForUnparseableValue() throws {
        let apr = try decodeAPR(value: "garbage", status: "AVAILABLE")
        XCTAssertNil(apr.fractionalRate)
    }

    // MARK: - Helpers

    private func decodeAPR(value: String, status: String?) throws -> AccountRootData.ResponseData.AccountNode.APR {
        var json = "{\"value\":\"\(value)\""
        if let status { json += ",\"status\":\"\(status)\"" }
        json += "}"
        return try JSONDecoder().decode(AccountRootData.ResponseData.AccountNode.APR.self, from: Data(json.utf8))
    }

    // MARK: - fetchStakePositions early-return paths
    //
    // The TCY/RUJI/SRUJI branches are driven through the injected
    // `THORChainStakingProviding`. STCY/YBRUNE still read `ThorchainService`
    // (a global singleton), so their branches remain uncovered — tracked under
    // [[projects/vultisig/defi-tab-fixes/architecture-review]] as the next
    // testability win.

    func testFetchStakePositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        // No RUNE coin in vault → guard short-circuits.
        let result = await THORChainStakeInteractor().fetchStakePositions(vault: vault)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - RUJI's two independent positions
    //
    // A Rujira account can hold a bonded position (claimable USDC, `account.*`)
    // and an auto-compounding one (sRUJI receipt, `liquid.*`) at the same time.
    // The interactor must report each on its own card: collapsing them lets one
    // side's zero hide the other side's balance, which is what disabled Unstake
    // for bonded-only holders.

    /// Live shape from the Rujira staking API for an account holding both sides.
    private func makeRujiDetails(bonded: Decimal, liquidSize: Decimal) -> StakingDetails {
        StakingDetails(
            stakedAmount: bonded,
            autoCompoundAmount: liquidSize,
            apr: 0.039662357617,
            estimatedReward: nil,
            nextPayoutDate: nil,
            rewards: Decimal(string: "31.12926996")!,
            rewardsCoin: CoinMeta(
                chain: .thorChain,
                ticker: "USDC",
                logo: "usdc",
                decimals: 6,
                priceProviderId: "usd-coin",
                contractAddress: "USDC",
                isNativeToken: false
            )
        )
    }

    private func makeRujiVault(staking: [CoinMeta], holding: [CoinMeta]) -> Vault {
        let vault = TestStore.makeVault()
        let address = "thor1fixturevaultaddress00000000000000000000"
        let hexPublicKey = "02" + String(repeating: "00", count: 32)
        vault.coins.append(Coin(asset: TokensStore.rune, address: address, hexPublicKey: hexPublicKey))
        for meta in holding {
            vault.coins.append(Coin(asset: meta, address: address, hexPublicKey: hexPublicKey))
        }
        vault.defiPositions.append(DefiPositions(chain: .thorChain, bonds: [], staking: staking, lps: []))
        return vault
    }

    private func position(_ dtos: [StakePositionData], ticker: String) throws -> StakePositionData {
        try XCTUnwrap(dtos.first { $0.coin.ticker.uppercased() == ticker.uppercased() })
    }

    func testVaultHoldingBothRujiPositionsGetsOneCardEach() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )
        let details = makeRujiDetails(
            bonded: Decimal(string: "16382.3899")!,
            liquidSize: Decimal(string: "14064.86651509")!
        )

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        XCTAssertEqual(dtos.count, 2)
        let bonded = try position(dtos, ticker: "RUJI")
        let compounded = try position(dtos, ticker: "SRUJI")
        XCTAssertEqual(bonded.amount, Decimal(string: "16382.3899"))
        XCTAssertEqual(bonded.type, .stake)
        XCTAssertEqual(compounded.amount, Decimal(string: "14064.86651509"))
        XCTAssertEqual(compounded.type, .compound)
    }

    /// The regression this fix exists for: a bonded-only holder used to see a
    /// zero card because the on-chain sRUJI receipt read (a genuine zero) won,
    /// and `canUnstake` keys off the displayed amount.
    func testBondedOnlyVaultKeepsAnUnstakableBondedCard() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )
        let details = makeRujiDetails(bonded: Decimal(string: "16382.3899")!, liquidSize: 0)

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        let bonded = try position(dtos, ticker: "RUJI")
        XCTAssertEqual(bonded.amount, Decimal(string: "16382.3899"))
        XCTAssertTrue(StakePosition(bonded, vault: vault).canUnstake)
        XCTAssertEqual(try position(dtos, ticker: "SRUJI").amount, 0)
    }

    /// The mirror-image regression: an auto-compounding holder must see the
    /// RUJI-denominated liquid size, and must be able to unstake it.
    func testAutoCompoundOnlyVaultKeepsAnUnstakableCompoundedCard() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )
        let details = makeRujiDetails(bonded: 0, liquidSize: Decimal(string: "14064.86651509")!)

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        let compounded = try position(dtos, ticker: "SRUJI")
        XCTAssertEqual(compounded.amount, Decimal(string: "14064.86651509"))
        XCTAssertTrue(StakePosition(compounded, vault: vault).canUnstake)
        XCTAssertEqual(try position(dtos, ticker: "RUJI").amount, 0)
    }

    /// Revenue on the auto-compounding side is reinvested rather than made
    /// claimable, so the APR and the pending USDC belong to the bonded card only
    /// — the compounded card is stat-free, like sTCY.
    func testAprAndClaimableRevenueRideOnTheBondedCardOnly() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )
        let details = makeRujiDetails(
            bonded: Decimal(string: "16382.3899")!,
            liquidSize: Decimal(string: "14064.86651509")!
        )

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        let bonded = try position(dtos, ticker: "RUJI")
        XCTAssertEqual(try XCTUnwrap(bonded.apr), 0.039662357617, accuracy: 1e-12)
        XCTAssertEqual(bonded.rewards, Decimal(string: "31.12926996"))
        XCTAssertEqual(bonded.rewardCoin?.ticker, "USDC")

        let compounded = try position(dtos, ticker: "SRUJI")
        XCTAssertNil(compounded.apr)
        XCTAssertNil(compounded.rewards)
        XCTAssertNil(compounded.rewardCoin)
    }

    /// An empty vault still gets both cards at zero, so the persisted rows are
    /// zeroed by the refresh rather than frozen at their last non-zero value
    /// (`upsert(stake:for:)` has no delete-stale), and there is a card to stake
    /// into.
    func testEmptyVaultStillReportsBothPositionsAtZero() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: makeRujiDetails(bonded: 0, liquidSize: 0)))
            .fetchStakePositions(vault: vault)

        XCTAssertEqual(dtos.count, 2)
        XCTAssertEqual(try position(dtos, ticker: "RUJI").amount, 0)
        XCTAssertEqual(try position(dtos, ticker: "SRUJI").amount, 0)
        XCTAssertFalse(StakePosition(try position(dtos, ticker: "SRUJI"), vault: vault).canUnstake)
    }

    func testOnlyEnabledPositionsAreReported() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )
        let details = makeRujiDetails(
            bonded: Decimal(string: "16382.3899")!,
            liquidSize: Decimal(string: "14064.86651509")!
        )

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        XCTAssertEqual(dtos.map { $0.coin.ticker.uppercased() }, ["RUJI"])
    }

    /// The opt-in migration enables sRUJI for every vault tracking RUJI, so the
    /// vaults that never held the receipt must stay one-card.
    func testEnabledPositionIsNotReportedWhenTheVaultDoesNotHoldTheCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji]
        )
        let details = makeRujiDetails(
            bonded: Decimal(string: "16382.3899")!,
            liquidSize: Decimal(string: "14064.86651509")!
        )

        let dtos = await THORChainStakeInteractor(stakingService: MockTHORChainStakingService(details: details))
            .fetchStakePositions(vault: vault)

        XCTAssertEqual(dtos.map { $0.coin.ticker.uppercased() }, ["RUJI"])
    }

    /// A failed read reports nothing so the persisted rows keep their last good
    /// amounts instead of flickering to zero.
    func testFailedStakingReadReportsNoPositions() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = makeRujiVault(
            staking: [TokensStore.ruji, TokensStore.sruji],
            holding: [TokensStore.ruji, TokensStore.sruji]
        )

        let dtos = await THORChainStakeInteractor(stakingService: FailingTHORChainStakingService())
            .fetchStakePositions(vault: vault)

        XCTAssertTrue(dtos.isEmpty)
    }

    // MARK: - liquidSize plumbing

    /// The auto-compounding amount has no other source, so the query must ask
    /// for it.
    func testRujiStakingQueryRequestsLiquidSize() throws {
        guard case .requestParameters(let body, _) = THORChainStakingAPI.getRujiStaking(address: "thor1abc").task else {
            return XCTFail("Expected a GraphQL body")
        }
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.contains("liquidSize"), "query must request liquidSize")
        XCTAssertTrue(query.contains("bonded"), "query must still request bonded")
    }

    /// Captured live from the Rujira endpoint for an account holding both
    /// positions (bonded 16382.3899 RUJI, 13855.94365632 sRUJI shares worth
    /// 14064.86651509 RUJI).
    func testAccountResponseDecodesBothPositions() throws {
        let json = """
        {"data":{"node":{"stakingV2":[{
          "account":"thor1qvmeavyusxyet7szr2azjzut7tamw4ycfg08ss",
          "bonded":{"amount":"1638238990000","asset":{"metadata":{"symbol":"RUJI"}}},
          "liquidSize":{"amount":"1406486651509"},
          "pendingRevenue":{"amount":"3112926996","asset":{"metadata":{"symbol":"USDC"}}},
          "pool":{"summary":{"apr":{"value":"39662357617","status":"AVAILABLE"}}}
        }]}}}
        """
        let decoded = try JSONDecoder().decode(AccountRootData.self, from: Data(json.utf8))
        let stake = try XCTUnwrap(decoded.data.node?.stakingV2?.first)

        XCTAssertEqual(stake.bonded.amount, "1638238990000")
        XCTAssertEqual(stake.liquidSize?.amount, "1406486651509")
        XCTAssertEqual(stake.pendingRevenue?.amount, "3112926996")
        XCTAssertEqual(try XCTUnwrap(stake.pool?.summary?.apr?.fractionalRate), 0.039662357617, accuracy: 1e-12)
    }

    // MARK: - Account payload → StakingDetails
    //
    // The base-unit scaling is the step that turns `1406486651509` into the
    // 14064.86651509 RUJI the card renders, and it is the same call the DeFi tab
    // makes in production.

    private func makeAccountResponse(
        bonded: String = "1638238990000",
        liquidSize: String? = "1406486651509",
        pendingRevenue: String = "3112926996",
        bondSymbol: String = "RUJI",
        extraPools: String = ""
    ) -> String {
        let liquidSizeField = liquidSize.map { "\"liquidSize\":{\"amount\":\"\($0)\"}," } ?? ""
        return """
        {"data":{"node":{"stakingV2":[\(extraPools){
          "account":"thor1qvmeavyusxyet7szr2azjzut7tamw4ycfg08ss",
          "bonded":{"amount":"\(bonded)","asset":{"metadata":{"symbol":"\(bondSymbol)"}}},
          \(liquidSizeField)
          "pendingRevenue":{"amount":"\(pendingRevenue)","asset":{"metadata":{"symbol":"USDC"}}},
          "pool":{"summary":{"apr":{"value":"39662357617","status":"AVAILABLE"}}}
        }]}}}
        """
    }

    private func makeDetails(from json: String) throws -> StakingDetails {
        let decoded = try JSONDecoder().decode(AccountRootData.self, from: Data(json.utf8))
        return try THORChainStakingService.makeRujiStakingDetails(from: decoded)
    }

    func testAccountPayloadScalesBothPositionsOutOfBaseUnits() throws {
        let details = try makeDetails(from: makeAccountResponse())

        XCTAssertEqual(details.stakedAmount, Decimal(string: "16382.3899"))
        XCTAssertEqual(details.autoCompoundAmount, Decimal(string: "14064.86651509"))
        XCTAssertEqual(details.rewards, Decimal(string: "31.12926996"))
        XCTAssertEqual(try XCTUnwrap(details.apr), 0.039662357617, accuracy: 1e-12)
        XCTAssertEqual(details.rewardsCoin?.ticker, "USDC")
        XCTAssertEqual(details.rewardsCoin?.decimals, 6)
    }

    /// The auto-compounding amount must NOT fall back to the bonded one — that
    /// substitution is the bug the split fixes.
    func testAccountPayloadKeepsTheTwoAmountsIndependent() throws {
        let bondedOnly = try makeDetails(from: makeAccountResponse(liquidSize: "0"))
        XCTAssertEqual(bondedOnly.stakedAmount, Decimal(string: "16382.3899"))
        XCTAssertEqual(bondedOnly.autoCompoundAmount, 0)

        let compoundOnly = try makeDetails(from: makeAccountResponse(bonded: "0"))
        XCTAssertEqual(compoundOnly.stakedAmount, 0)
        XCTAssertEqual(compoundOnly.autoCompoundAmount, Decimal(string: "14064.86651509"))
    }

    /// `stakingV2` holds one entry per Rujira staking pool the account touches
    /// and the RUJI one is not necessarily first, so the pool is selected by its
    /// bond-asset symbol.
    func testAccountPayloadSelectsTheRujiPoolNotTheFirstOne() throws {
        let otherPool = """
        {"account":"thor1other","bonded":{"amount":"999900000000","asset":{"metadata":{"symbol":"TCY"}}},
         "liquidSize":{"amount":"888800000000"},
         "pendingRevenue":{"amount":"0","asset":{"metadata":{"symbol":"USDC"}}}},
        """
        let details = try makeDetails(from: makeAccountResponse(extraPools: otherPool))

        XCTAssertEqual(details.stakedAmount, Decimal(string: "16382.3899"))
        XCTAssertEqual(details.autoCompoundAmount, Decimal(string: "14064.86651509"))
    }

    func testAccountPayloadWithoutARujiPoolIsAGenuineZero() throws {
        let details = try makeDetails(from: makeAccountResponse(bondSymbol: "TCY"))

        XCTAssertEqual(details.stakedAmount, 0)
        XCTAssertEqual(details.autoCompoundAmount, 0)
    }

    /// A partial response must fail rather than report a zero, which would erase
    /// a live position on the next upsert.
    func testAccountPayloadWithoutALiquidSizeFailsClosed() {
        XCTAssertThrowsError(try makeDetails(from: makeAccountResponse(liquidSize: nil)))
    }

    func testAccountPayloadWithAnUnparseableBondedAmountFailsClosed() {
        XCTAssertThrowsError(try makeDetails(from: makeAccountResponse(bonded: "not-a-number")))
    }

    func testAccountPayloadWithAnUnparseableLiquidSizeFailsClosed() {
        XCTAssertThrowsError(try makeDetails(from: makeAccountResponse(liquidSize: "not-a-number")))
    }

    /// Revenue is a claim CTA on an otherwise-complete card, so an unparseable
    /// value must not take the two position balances down with it.
    func testAccountPayloadKeepsTheBalancesWhenRevenueIsUnparseable() throws {
        let details = try makeDetails(from: makeAccountResponse(pendingRevenue: "not-a-number"))

        XCTAssertEqual(details.stakedAmount, Decimal(string: "16382.3899"))
        XCTAssertEqual(details.autoCompoundAmount, Decimal(string: "14064.86651509"))
        XCTAssertEqual(details.rewards, 0)
    }

    func testAccountPayloadWithoutANodeFailsClosed() {
        XCTAssertThrowsError(try makeDetails(from: #"{"data":{"node":null}}"#))
    }

    func testAccountPayloadWithoutStakingEntriesFailsClosed() {
        XCTAssertThrowsError(try makeDetails(from: #"{"data":{"node":{"stakingV2":null}}}"#))
    }

    // MARK: - "no longer a staker" is an answer, not a failure

    /// ⚠️ **The exact body THORNode returns after a full TCY unstake.** It is a
    /// 500, so absence and a server fault share a status code, and swallowing
    /// the wrong one either strands a stale balance on the card or zeroes a
    /// funded position on an outage.
    func test_isTcyStakerAbsent_recognisesTheNonStakerBody() {
        let body = Data(#"{"code":2, "message":"fail to tcy staker: TCYStaker doesn't exist: thor1pe0pspu4ep85gxr5h9l6k49g024vemtr80hg4c", "details":[]}"#.utf8)
        XCTAssertTrue(THORChainStakingService.isTcyStakerAbsent(HTTPError.statusCode(500, body)))
    }

    /// A 500 that is not this answer must keep throwing, so the persisted row
    /// keeps its last good value rather than being zeroed by an outage.
    func test_isTcyStakerAbsent_refusesEveryOtherFailure() {
        let genuine = Data(#"{"code":13,"message":"internal server error","details":[]}"#.utf8)
        XCTAssertFalse(THORChainStakingService.isTcyStakerAbsent(HTTPError.statusCode(500, genuine)))
        XCTAssertFalse(THORChainStakingService.isTcyStakerAbsent(HTTPError.statusCode(500, nil)))
        XCTAssertFalse(THORChainStakingService.isTcyStakerAbsent(HTTPError.timeout))
        XCTAssertFalse(THORChainStakingService.isTcyStakerAbsent(HTTPError.invalidResponse))
    }

    /// Not keyed on the status code: THORNode uses 500 today, and the reading
    /// should survive it being corrected to a 404 without a code change.
    func test_isTcyStakerAbsent_isNotKeyedOnTheStatusCode() {
        let body = Data(#"{"code":2, "message":"fail to tcy staker: TCYStaker doesn't exist: thor1abc", "details":[]}"#.utf8)
        XCTAssertTrue(THORChainStakingService.isTcyStakerAbsent(HTTPError.statusCode(404, body)))
    }
}

// MARK: - The conversion the predicate guards

/// `isTcyStakerAbsent` is only the predicate. The substitution it authorises —
/// a recognised absence becoming `TcyStakerResponse(amount: "0")` instead of a
/// throw — lives in `fetchTcyStakedAmount`, which is what the DeFi tab actually
/// calls. These drive that method over a stubbed transport so both halves are
/// pinned end to end: the absence reads as a zero, and everything else still
/// throws rather than being quietly zeroed.
///
/// `THORChainStakingService` builds its `HTTPClient` on `URLSession.shared`, so
/// the seam is a globally registered `URLProtocol` scoped to the `tcy_staker`
/// route — the same interception the join-keysign and Sui service tests use.
@MainActor
final class THORChainStakingServiceTcyStakerTests: XCTestCase {

    private let address = "thor1pe0pspu4ep85gxr5h9l6k49g024vemtr80hg4c"

    /// ⚠️ **The exact body THORNode returns after a full TCY unstake.**
    private var nonStakerBody: Data {
        Data(#"{"code":2, "message":"fail to tcy staker: TCYStaker doesn't exist: \#(address)", "details":[]}"#.utf8)
    }

    override func setUp() {
        super.setUp()
        TcyStakerStubProtocol.reset()
        URLProtocol.registerClass(TcyStakerStubProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(TcyStakerStubProtocol.self)
        TcyStakerStubProtocol.reset()
        super.tearDown()
    }

    /// The live shape: absence arrives as a 500, and must come back as a zero
    /// position rather than a throw that leaves the withdrawn balance on screen.
    func testFetchTcyStakedAmountReadsA500NonStakerAsZero() async throws {
        TcyStakerStubProtocol.configure(statusCode: 500, body: nonStakerBody)

        let response = try await THORChainStakingService.shared.fetchTcyStakedAmount(address: address)

        XCTAssertEqual(response.amount, "0")
        XCTAssertEqual(TcyStakerStubProtocol.requestCount, 1)
        XCTAssertTrue(
            TcyStakerStubProtocol.lastPath?.hasSuffix("/thorchain/tcy_staker/\(address)") == true,
            "The stub must have answered the tcy_staker route, got \(TcyStakerStubProtocol.lastPath ?? "nil")"
        )
    }

    /// Not keyed on the status code: the same body behind a 404 must read the
    /// same way, so THORNode correcting the status doesn't need a code change.
    func testFetchTcyStakedAmountReadsA404NonStakerAsZero() async throws {
        TcyStakerStubProtocol.configure(statusCode: 404, body: nonStakerBody)

        let response = try await THORChainStakingService.shared.fetchTcyStakedAmount(address: address)

        XCTAssertEqual(response.amount, "0")
    }

    /// A genuine server fault shares the 500 with the absence, and must still
    /// throw — the persisted row keeping its last good value is the right answer
    /// to a read that did not happen.
    func testFetchTcyStakedAmountPropagatesAnUnrelatedFailure() async {
        let fault = Data(#"{"code":13,"message":"internal server error","details":[]}"#.utf8)
        TcyStakerStubProtocol.configure(statusCode: 500, body: fault)

        do {
            let response = try await THORChainStakingService.shared.fetchTcyStakedAmount(address: address)
            XCTFail("An outage must not be converted to a zero position, got amount \(response.amount)")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected the status-code error to propagate, got \(error)")
        }
    }

    /// The zero substitution must not swallow a real balance on the way past.
    func testFetchTcyStakedAmountReturnsTheStakedAmountOnSuccess() async throws {
        TcyStakerStubProtocol.configure(statusCode: 200, body: Data(#"{"amount":"1638238990000"}"#.utf8))

        let response = try await THORChainStakingService.shared.fetchTcyStakedAmount(address: address)

        XCTAssertEqual(response.amount, "1638238990000")
    }
}

/// Answers only the `tcy_staker` route, so registering it globally leaves every
/// other request in the suite untouched.
private final class TcyStakerStubProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var statusCode = 200
    private static var body = Data("{}".utf8)
    private static var count = 0
    private static var path: String?

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// The path that actually went on the wire, so a passing test cannot be one
    /// where the stub answered some other request.
    static var lastPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }

    static func configure(statusCode: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.body = body
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 200
        body = Data("{}".utf8)
        count = 0
        path = nil
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("/thorchain/tcy_staker/") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        // Counted here rather than in `canInit`, which URLSession may consult
        // more than once for a single load.
        Self.lock.lock()
        let code = Self.statusCode
        let payload = Self.body
        Self.count += 1
        Self.path = request.url?.path
        Self.lock.unlock()

        // Force-unwrap is safe: the URL came from the intercepted request and
        // every status code used here initializes a response.
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
