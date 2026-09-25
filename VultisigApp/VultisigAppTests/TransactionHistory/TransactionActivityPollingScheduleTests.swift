import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityPollingScheduleTests: XCTestCase {
    func testNativeRecordsReuseEveryForegroundChainInterval() {
        for chain in Chain.allCases {
            let row = ActivityTestFixture.row(chain: chain)
            XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: row), ChainStatusConfig.config(for: chain).pollInterval)
        }
    }

    func testSwapProvidersReuseTheirForegroundDefaultsInsteadOfInboundChainInterval() {
        for (provider, expected) in [
            (SwapKitTrackingService.providerKind, SwapKitTrackingService.baseInterval),
            (NativeSwapTrackingService.providerKind, NativeSwapTrackingService.baseInterval),
            (THORChainLimitTrackingService.providerKind, THORChainLimitTrackingService.baseInterval)
        ] {
            let row = ActivityTestFixture.row(chain: .bitcoin, type: .swap, tracking: .init(providerKind: provider))
            XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: row), expected)
        }
        let source = ActivityTestFixture.row(chain: .bitcoin, type: .swap,
            tracking: .init(providerKind: TransactionActivityPolicy.nativeSourceProviderKind))
        XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: source), ChainStatusConfig.config(for: .bitcoin).pollInterval)
    }

    func testFastChainDoesNotAccelerateSlowChainAndRemainingWorkControlsWakeRequest() {
        var schedule = TransactionActivityPollingSchedule()
        let fast = ActivityTestFixture.row(chain: .solana)
        let slow = ActivityTestFixture.row(chain: .bitcoin)
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(schedule.nextDelay(for: [fast, slow], now: now), 2)
        XCTAssertTrue(schedule.shouldObserve(fast, now: now))
        XCTAssertTrue(schedule.shouldObserve(slow, now: now))
        schedule.didObserve(fast, now: now)
        schedule.didObserve(slow, now: now)
        XCTAssertFalse(schedule.shouldObserve(fast, now: now.addingTimeInterval(1)))
        XCTAssertTrue(schedule.shouldObserve(fast, now: now.addingTimeInterval(2)))
        XCTAssertFalse(schedule.shouldObserve(slow, now: now.addingTimeInterval(2)))
        schedule.didObserve(fast, now: now.addingTimeInterval(2))
        XCTAssertEqual(schedule.nextDelay(for: [fast, slow], now: now.addingTimeInterval(2)), 2)
        // Once the fast record ends, only the slow record determines the next request.
        XCTAssertEqual(schedule.nextDelay(for: [slow], now: now.addingTimeInterval(2)), 28)
        XCTAssertTrue(schedule.shouldObserve(slow, now: now.addingTimeInterval(30)))
        XCTAssertEqual(schedule.nextDelay(for: [slow], now: now.addingTimeInterval(35)), 0)
    }

    func testExistingProviderPollPreservesRemainingIntervalWithoutMovingCompletedObservationBackwards() {
        var schedule = TransactionActivityPollingSchedule()
        let row = ActivityTestFixture.row(type: .limit,
            tracking: .init(providerKind: THORChainLimitTrackingService.providerKind))
        let now = Date(timeIntervalSince1970: 1000)
        schedule.didObserve(row, now: now.addingTimeInterval(-50))
        XCTAssertFalse(schedule.shouldObserve(row, now: now))
        XCTAssertEqual(schedule.nextDelay(for: [row], now: now), 10)
        XCTAssertTrue(schedule.shouldObserve(row, now: now.addingTimeInterval(10)))
        schedule.didObserve(row, now: now.addingTimeInterval(12))
        schedule.didObserve(row, now: now.addingTimeInterval(10))
        XCTAssertEqual(schedule.nextDelay(for: [row], now: now.addingTimeInterval(12)), 60)
    }

    func testNextPollIsMeasuredAfterObservationCompletes() {
        var schedule = TransactionActivityPollingSchedule()
        let row = ActivityTestFixture.row(chain: .ethereum)
        let completion = Date(timeIntervalSince1970: 1010)
        schedule.didObserve(row, now: completion)
        XCTAssertFalse(schedule.shouldObserve(row, now: completion.addingTimeInterval(4)))
        XCTAssertTrue(schedule.shouldObserve(row, now: completion.addingTimeInterval(5)))
        XCTAssertEqual(schedule.nextDelay(for: [row], now: completion), 5)
    }

    func testStaleWindowFloorsFastCadencesToASaneBackgroundMinimum() {
        let fast = ActivityTestFixture.row(chain: .solana)
        XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: fast), 2)
        XCTAssertEqual(TransactionActivityStaleness.window(for: fast), TransactionActivityStaleness.floor)
    }

    func testStaleWindowScalesWithSlowerChainAndProviderCadences() {
        let bitcoin = ActivityTestFixture.row(chain: .bitcoin)
        XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: bitcoin), 30)
        XCTAssertEqual(TransactionActivityStaleness.window(for: bitcoin),
                       max(TransactionActivityStaleness.floor, 30 * TransactionActivityStaleness.multiplier))

        let limitOrder = ActivityTestFixture.row(chain: .bitcoin, type: .swap,
            tracking: .init(providerKind: THORChainLimitTrackingService.providerKind))
        XCTAssertEqual(TransactionActivityPollingSchedule.interval(for: limitOrder), THORChainLimitTrackingService.baseInterval)
        XCTAssertEqual(TransactionActivityStaleness.window(for: limitOrder),
                       max(TransactionActivityStaleness.floor, THORChainLimitTrackingService.baseInterval * TransactionActivityStaleness.multiplier))
        XCTAssertGreaterThan(TransactionActivityStaleness.window(for: limitOrder), TransactionActivityStaleness.floor)
    }
}
