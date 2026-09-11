#if os(iOS)
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityBackgroundRunnerTests: XCTestCase {
    private var system: BackgroundRuntimeSpy!
    private var clock: BackgroundTestClock!
    private var work = true
    private var foreground = false

    override func setUp() async throws {
        system = BackgroundRuntimeSpy()
        clock = BackgroundTestClock()
        work = true
        foreground = false
    }

    private func runner(drain: @escaping () async -> Void = {}, refresh: @escaping () async -> Void = {}) -> TransactionActivityBackgroundRunner {
        TransactionActivityBackgroundRunner(runtime: system.runtime, hasWork: { [unowned self] in self.work },
                                            isForeground: { [unowned self] in self.foreground }, refresh: refresh, drain: drain,
                                            sleep: { [clock] in try await clock!.sleep($0) })
    }

    func testNoWorkAndForegroundNeverAcquireRuntime() {
        let runner = runner()
        work = false
        runner.enteredBackground()
        work = true
        foreground = true
        runner.enteredBackground()
        XCTAssertTrue(system.expirations.isEmpty)
        XCTAssertTrue(system.scheduled.isEmpty)
    }

    func testContinuationRefreshesThenEndsWhenWorkCompletes() async {
        let observed = expectation(description: "observed")
        let runner = runner { self.work = false; observed.fulfill() }
        runner.enteredBackground()
        await fulfillment(of: [observed], timeout: 2)
        await drain()
        XCTAssertEqual(system.ended.count, 1)
        XCTAssertEqual(system.scheduled.count, 1)
        XCTAssertGreaterThan(system.scheduled[0].timeIntervalSinceNow, 890)
        runner.enteredForeground()
        XCTAssertEqual(system.ended.count, 1)
    }

    func testScheduledCompletionWaitsForObservationAndOnlyRunsOnce() async {
        let entered = expectation(description: "entered")
        var release: CheckedContinuation<Void, Never>?
        let runner = runner {
            await withCheckedContinuation { release = $0; entered.fulfill() }
        }
        var results: [Bool] = []
        let expire = runner.performScheduledRefresh { results.append($0) }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(results.isEmpty)
        release?.resume()
        await drain()
        XCTAssertEqual(results, [true])
        XCTAssertTrue(system.expirations.isEmpty)
        expire()
        XCTAssertEqual(results, [true])
        XCTAssertEqual(system.scheduled.count, 1)
    }

    func testExpirationCompletesWithoutWaitingForUncooperativeNetwork() async {
        let entered = expectation(description: "entered")
        var release: CheckedContinuation<Void, Never>?
        let runner = runner {
            await withCheckedContinuation { release = $0; entered.fulfill() }
        }
        var results: [Bool] = []
        let expire = runner.performScheduledRefresh { results.append($0) }
        await fulfillment(of: [entered], timeout: 2)
        expire()
        expire()
        XCTAssertEqual(results, [false])
        release?.resume()
        await drain()
        XCTAssertEqual(results, [false])
    }

    func testOldExpirationCannotFinishReplacementWindow() async {
        let runner = runner()
        runner.enteredBackground()
        let oldExpiration = system.expirations[0]
        foreground = true
        runner.enteredForeground()
        foreground = false
        runner.enteredBackground()
        oldExpiration()
        XCTAssertEqual(system.ended.count, 1)
        XCTAssertEqual(system.expirations.count, 2)
        runner.enteredForeground()
        await drain()
        XCTAssertEqual(system.ended.count, 2)
    }

    func testDeadlineStopsContinuationAndDoesNotRenewFromStatusEvents() async {
        var observations = 0
        let runner = runner { observations += 1 }
        runner.enteredBackground()
        await drain()
        XCTAssertEqual(observations, 1)
        clock.advance(.seconds(10))
        await drain()
        XCTAssertEqual(observations, 2)
        runner.trackingDidChange()
        runner.enteredBackground()
        XCTAssertEqual(system.scheduled.count, 1)
        XCTAssertEqual(system.expirations.count, 1)
        clock.advance(.seconds(25))
        await drain()
        XCTAssertEqual(system.ended.count, 1)
    }

    func testSchedulingDenialDoesNotPreventContinuationAndInvalidAssertionDoesNotRun() async {
        system.denyScheduling = true
        let observed = expectation(description: "observed")
        let first = runner { observed.fulfill() }
        first.enteredBackground()
        await fulfillment(of: [observed], timeout: 2)
        first.enteredForeground()
        system.denyAssertion = true
        let second = runner { XCTFail("No runtime granted") }
        second.enteredBackground()
        await drain()
        XCTAssertEqual(system.ended.count, 1)
    }

    func testSynchronousExpirationReleasesReturnedAssertionAndDeletionCancelsSchedule() async {
        system.expireImmediately = true
        let runner = runner { XCTFail("Already expired") }
        runner.enteredBackground()
        XCTAssertEqual(system.ended.count, 1)
        work = false
        runner.trackingDidChange()
        XCTAssertGreaterThan(system.cancelCount, 0)
        await drain()
    }

    func testSoftDeadlineDrainsButHardDeadlineAlwaysReleasesRuntime() async {
        let draining = expectation(description: "draining")
        var release: CheckedContinuation<Void, Never>?
        let runner = runner(drain: {
            await withCheckedContinuation { release = $0; draining.fulfill() }
        })
        runner.enteredBackground()
        await drain()
        clock.advance(.seconds(22))
        await fulfillment(of: [draining], timeout: 2)
        XCTAssertTrue(system.ended.isEmpty)
        clock.advance(.seconds(25))
        await drain()
        XCTAssertEqual(system.ended.count, 1)
        release?.resume()
        await drain()
        XCTAssertEqual(system.ended.count, 1)
    }

    func testScheduledDeliveryPreservesContinuationAndOnlySchedulesFromBackground() async {
        let runner = runner()
        foreground = true
        runner.trackingDidChange()
        XCTAssertTrue(system.scheduled.isEmpty)
        foreground = false
        runner.enteredBackground()
        var completions: [Bool] = []
        let expire = runner.performScheduledRefresh { completions.append($0) }
        expire()
        XCTAssertEqual(completions, [true])
        XCTAssertTrue(system.ended.isEmpty)
        XCTAssertEqual(system.expirations.count, 1)
        XCTAssertEqual(system.scheduled.count, 2)
        runner.enteredForeground()
        await drain()
    }

    func testLockedDeviceCanInitializeWithReadableLedgerButDoesNotCacheUnavailableDefaults() throws {
        let ledger = try JSONEncoder().encode([String: TransactionLiveActivityCoordinator.Binding]())
        XCTAssertTrue(TransactionActivityBackgroundService.canInitialize(protectedDataAvailable: false, ledger: ledger))
        XCTAssertFalse(TransactionActivityBackgroundService.canInitialize(protectedDataAvailable: false, ledger: nil))
        XCTAssertFalse(TransactionActivityBackgroundService.canInitialize(protectedDataAvailable: false, ledger: Data("invalid".utf8)))
        XCTAssertTrue(TransactionActivityBackgroundService.canInitialize(protectedDataAvailable: true, ledger: nil))
    }

    private func drain() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

@MainActor
private final class BackgroundRuntimeSpy {
    var expirations: [@MainActor () -> Void] = []
    var ended: [UUID] = []
    var scheduled: [Date] = []
    var cancelCount = 0
    var denyAssertion = false
    var denyScheduling = false
    var expireImmediately = false
    var runtime: TransactionActivityBackgroundRunner.Runtime {
        .init(begin: { [self] expiration in
            expirations.append(expiration)
            if expireImmediately { expiration() }
            return denyAssertion ? nil : UUID()
        }, end: { [self] in ended.append($0) }, schedule: { [self] in
            if denyScheduling { throw URLError(.notConnectedToInternet) }
            scheduled.append($0)
        }, cancelScheduled: { [self] in cancelCount += 1 })
    }
}

@MainActor
private final class BackgroundTestClock {
    private var waiters: [UUID: (Duration, CheckedContinuation<Void, Error>)] = [:]
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = (duration, continuation)
                }
            }
        } onCancel: {
            Task { @MainActor in self.waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
        }
    }
    func advance(_ duration: Duration) {
        for (id, waiter) in waiters where waiter.0 == duration {
            waiters.removeValue(forKey: id)?.1.resume()
        }
    }
}
#endif
