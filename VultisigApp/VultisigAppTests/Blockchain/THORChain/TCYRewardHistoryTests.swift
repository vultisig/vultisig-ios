//
//  TCYRewardHistoryTests.swift
//  VultisigAppTests
//
//  Fixtures follow mainnet Midgard `/v2/tcy/distribution/{address}`:
//  `{address, apr, total, distributions: [{amount, date, price}] | null}`.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TCYRewardHistoryTests: XCTestCase {

    private func history(_ json: String) throws -> [BondRewardHistoryEntry] {
        let response = try JSONDecoder().decode(TcyUserDistributionsResponse.self, from: Data(json.utf8))
        return THORChainStakingService.makeTcyRewardHistory(from: response.distributions)
    }

    private func response(rows: [(amount: String, date: String)]) -> String {
        let entries = rows.map { "{\"amount\":\"\($0.amount)\",\"date\":\"\($0.date)\",\"price\":\"52000000\"}" }
        return """
        {
            "address": "thor1tcystaker",
            "apr": "0.12",
            "distributions": [\(entries.joined(separator: ","))],
            "total": "0"
        }
        """
    }

    // MARK: - Parsing

    /// A non-staker gets HTTP 200 with `"distributions": null`.
    func testNullDistributionsGiveNoRows() throws {
        let rows = try history("""
        {"address": "thor1tcystaker", "apr": "0", "distributions": null, "total": "0"}
        """)

        XCTAssertEqual(rows, [])
    }

    func testUnsortedRowsComeBackNewestFirst() throws {
        let rows = try history(response(rows: [
            ("200", "1700086400"),
            ("300", "1700172800"),
            ("100", "1700000000")
        ]))

        XCTAssertEqual(rows.map(\.id), [1_700_172_800, 1_700_086_400, 1_700_000_000])
        XCTAssertEqual(rows.map(\.amount), [300, 200, 100])
    }

    /// Unix seconds. Read as nanoseconds (the bond churn conversion) this
    /// would land in January 1970.
    func testDateIsReadAsUnixSeconds() throws {
        let rows = try history(response(rows: [("12345", "1700000000")]))

        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.date, Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The sheet formats amounts with the RUNE coin, which divides by 1e8,
    /// so the parser must not scale them.
    func testAmountStaysInRuneBaseUnits() throws {
        let rows = try history(response(rows: [("123456789", "1700000000")]))

        XCTAssertEqual(rows.first?.amount, Decimal(123_456_789))
    }

    func testUnparseableOrNonPositiveRowsAreDropped() throws {
        let rows = try history(response(rows: [
            ("500", "1700000000"),
            ("abc", "1700000001"),
            ("12abc", "1700000002"),
            ("0", "1700000003"),
            ("-5", "1700000004"),
            ("1.5", "1700000005"),
            ("600", ""),
            ("700", "0"),
            ("800", "not-a-date"),
            ("900", "1700000009")
        ]))

        XCTAssertEqual(rows.map(\.id), [1_700_000_009, 1_700_000_000])
        XCTAssertEqual(rows.map(\.amount), [900, 500])
    }

    // MARK: - Sheet view model

    /// The header total is the sum of the parsed rows, not Midgard's `total`
    /// field (the fixture's says "0"), so the header always equals the list.
    func testTotalEqualsTheSumOfTheRows() async throws {
        let rows = try history(response(rows: [
            ("150000000", "1700000000"),
            ("25000000", "1700086400"),
            ("5", "1700172800")
        ]))
        let viewModel = BondRewardHistoryViewModel(
            coin: .example,
            subtitle: String(format: "stakedCoin".localized, TokensStore.tcy.ticker),
            upcomingAmount: 0,
            fetchHistory: { BondRewardHistory(entries: rows, isComplete: true) }
        )

        viewModel.load()
        await waitUntil { !viewModel.isLoading }
        XCTAssertFalse(viewModel.isLoading)

        XCTAssertEqual(viewModel.total, Decimal(175_000_005))
        XCTAssertEqual(viewModel.history.count, 3)
    }

    func testNoPayoutsGiveAZeroTotalAndNoError() async throws {
        let rows = try history("""
        {"address": "thor1tcystaker", "apr": "0", "distributions": null, "total": "0"}
        """)
        let viewModel = BondRewardHistoryViewModel(
            coin: .example,
            subtitle: String(format: "stakedCoin".localized, TokensStore.tcy.ticker),
            upcomingAmount: 0,
            fetchHistory: { BondRewardHistory(entries: rows, isComplete: true) }
        )

        viewModel.load()
        await waitUntil { !viewModel.isLoading }
        XCTAssertFalse(viewModel.isLoading)

        XCTAssertEqual(viewModel.total, 0)
        XCTAssertNil(viewModel.loadError)
    }

    /// The card's estimate is whole RUNE; the sheet's rows are base units.
    /// `Coin.example` has 8 decimals, like RUNE.
    func testUpcomingIsTheCardEstimateInBaseUnits() {
        let viewModel = BondRewardHistoryViewModel(
            tcyStakerAddress: "thor1tcystaker",
            runeCoin: .example,
            estimatedReward: Decimal(string: "0.5")!
        )

        XCTAssertEqual(viewModel.upcomingAmount, Decimal(50_000_000))
        XCTAssertEqual(viewModel.subtitle, String(format: "stakedCoin".localized, TokensStore.tcy.ticker))
    }

    /// The history stays reachable without an estimate; only the Upcoming row goes.
    func testNoEstimateLeavesUpcomingOut() {
        let viewModel = BondRewardHistoryViewModel(
            tcyStakerAddress: "thor1tcystaker",
            runeCoin: .example,
            estimatedReward: nil
        )

        XCTAssertNil(viewModel.upcomingAmount)
    }

    // MARK: - Which card is tappable

    func testOnlyThePlainTCYStakeHasRewardHistory() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        func isTCYStake(_ coin: CoinMeta) -> Bool {
            StakePosition(coin: coin, type: StakePositionType.defaultType(for: coin), amount: 10, vault: vault).isTCYStake
        }

        XCTAssertTrue(isTCYStake(TokensStore.tcy))
        XCTAssertFalse(isTCYStake(TokensStore.stcy))
        XCTAssertFalse(isTCYStake(TokensStore.ytcy))
        XCTAssertFalse(isTCYStake(TokensStore.ruji))
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
