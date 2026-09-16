import Combine
import XCTest
@testable import VultisigApp

@MainActor
final class FastVaultRoutingViewModelTests: XCTestCase {
    private var store: TestContextToken?
    private var subscriptions = Set<AnyCancellable>()

    override func setUp() async throws {
        store = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        subscriptions.removeAll()
        TestStore.restore(store)
        store = nil
    }

    private func makeVault() -> Vault {
        let vault = TestStore.makeVault(pubKey: UUID().uuidString)
        vault.localPartyID = "device"
        vault.signers = ["device", "server-fixture"]
        return vault
    }

    private func idleExpectation(_ model: FastVaultRoutingViewModel) -> XCTestExpectation {
        let idle = expectation(description: "route check finishes")
        model.$isChecking.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in idle.fulfill() }.store(in: &subscriptions)
        return idle
    }

    func testFreshBackgroundConfirmationRoutesWithoutAnotherRequestOrLoading() async {
        let vault = makeVault()
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in calls += 1; return .present }, saveStorage: {}
        )
        await refresher.refreshAllIfStale([vault])
        let model = FastVaultRoutingViewModel(refresher: refresher)
        var routes: [Bool] = []
        model.resolve(vault) { routes.append($0) }
        XCTAssertEqual(routes, [true])
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.isChecking)
    }

    func testRoutingConfirmationExpiresAtSixtySecondsDespiteBackgroundTTL() async {
        let vault = makeVault()
        var now = Date(timeIntervalSince1970: 1_000)
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in calls += 1; return .present }, saveStorage: {}, now: { now }
        )
        await refresher.refresh(vault)
        now = now.addingTimeInterval(59)
        XCTAssertEqual(refresher.confirmedPresenceForRouting(vault), .present)
        now = now.addingTimeInterval(1)
        XCTAssertNil(refresher.confirmedPresenceForRouting(vault))
        await refresher.refreshIfStale(vault)
        XCTAssertEqual(calls, 1)
        let outcome = await refresher.presenceForRouting(vault)
        XCTAssertEqual(outcome, .present)
        XCTAssertEqual(calls, 2)
    }

    func testChangedTopologyAndBackwardClockInvalidateRoutingConfirmation() async {
        let vault = makeVault()
        var now = Date(timeIntervalSince1970: 1_000)
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .present }, saveStorage: {}, now: { now }
        )
        await refresher.refresh(vault)
        now = now.addingTimeInterval(-1)
        XCTAssertNil(refresher.confirmedPresenceForRouting(vault))
        now = now.addingTimeInterval(1)
        vault.signers = ["device", "server-replacement"]
        XCTAssertNil(refresher.confirmedPresenceForRouting(vault))
    }

    func testUnknownDoesNotRouteUsingEarlierFreshSuccessAndRetryRecovers() async {
        let vault = makeVault()
        var result: FastVaultPresence = .present
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in result }, saveStorage: {}
        )
        await refresher.refresh(vault)
        result = .unknown(.requestFailed)
        await refresher.refresh(vault)
        let model = FastVaultRoutingViewModel(refresher: refresher)
        var routes: [Bool] = []
        let failed = idleExpectation(model)
        model.resolve(vault) { routes.append($0) }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(model.hasError)
        XCTAssertTrue(routes.isEmpty)
        XCTAssertTrue(vault.offersFastSigning)
        result = .present
        let retried = idleExpectation(model)
        model.resolve(vault) { routes.append($0) }
        await fulfillment(of: [retried], timeout: 2)
        XCTAssertEqual(routes, [true])
        XCTAssertFalse(model.hasError)
    }

    func testPrefetchAndRepeatedTapShareOnePendingRequest() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "background request starts")
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            calls += 1
            return await withCheckedContinuation { release = $0; started.fulfill() }
        }, saveStorage: {})
        let model = FastVaultRoutingViewModel(refresher: refresher)
        let prefetch = Task { await model.prefetch(vault) }
        await fulfillment(of: [started], timeout: 2)
        var routes: [Bool] = []
        let idle = idleExpectation(model)
        model.resolve(vault) { routes.append($0) }
        model.resolve(vault) { routes.append($0) }
        XCTAssertTrue(model.isChecking)
        XCTAssertTrue(routes.isEmpty)
        release?.resume(returning: .present)
        await prefetch.value
        await fulfillment(of: [idle], timeout: 2)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(routes, [true])
    }

    func testPairedChoiceIgnoresLateBackgroundSuccess() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "background request starts")
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            await withCheckedContinuation { release = $0; started.fulfill() }
        }, saveStorage: {})
        let model = FastVaultRoutingViewModel(refresher: refresher)
        let prefetch = Task { await model.prefetch(vault) }
        await fulfillment(of: [started], timeout: 2)
        var routes: [Bool] = []
        let lateRoute = expectation(description: "cancelled action cannot navigate")
        lateRoute.isInverted = true
        model.resolve(vault) { _ in lateRoute.fulfill() }
        await Task.yield()
        model.cancel()
        routes.append(false)
        XCTAssertFalse(model.isChecking)
        release?.resume(returning: .present)
        await prefetch.value
        await fulfillment(of: [lateRoute], timeout: 0.1)
        // A later action may use the background result, but the cancelled
        // action must never navigate after the explicit paired choice.
        model.resolve(vault) { routes.append($0) }
        XCTAssertEqual(routes, [false, true])
    }

    func testLeavingScreenDuringActiveRequestSuppressesNavigation() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "action request is awaiting response")
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            await withCheckedContinuation { release = $0; started.fulfill() }
        }, saveStorage: {})
        let model = FastVaultRoutingViewModel(refresher: refresher)
        let lateRoute = expectation(description: "departed screen cannot navigate")
        lateRoute.isInverted = true
        model.resolve(vault) { _ in lateRoute.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        model.cancel()
        release?.resume(returning: .present)
        await fulfillment(of: [lateRoute], timeout: 0.1)
        XCTAssertFalse(model.isChecking)
        XCTAssertFalse(model.hasError)
    }

    func testPairedUpgradeDoesNotRepeatReviewedBackupInstructions() throws {
        let vault = makeVault()
        let screen = AllDevicesUpgradeView(vault: vault, hasReviewedBackups: true)
        let route = try XCTUnwrap(screen.nextRoute as? KeygenRoute)
        guard case .peerDiscovery(let tssType, let routeVault, let selectedTab, let config, _, _, _) = route else {
            return XCTFail("Reviewed backups must continue to paired discovery")
        }
        XCTAssertEqual(tssType, .Migrate)
        XCTAssertTrue(routeVault === vault)
        XCTAssertEqual(selectedTab, .secure)
        XCTAssertNil(config)
    }

    func testSecureUpgradeStillRequiresBackupInstructions() throws {
        let vault = makeVault()
        let screen = AllDevicesUpgradeView(vault: vault)
        let route = try XCTUnwrap(screen.nextRoute as? VaultRoute)
        XCTAssertEqual(route, .vaultShareBackups(vault: vault))
    }

    func testColdUnknownLeavesNavigationForExplicitUserChoice() async {
        let vault = makeVault()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .unknown(.requestFailed) }, saveStorage: {}
        )
        let model = FastVaultRoutingViewModel(refresher: refresher)
        let idle = idleExpectation(model)
        model.resolve(vault) { _ in XCTFail("Unknown cannot select either route") }
        await fulfillment(of: [idle], timeout: 2)
        XCTAssertTrue(model.hasError)
        model.cancel()
        XCTAssertFalse(model.hasError)
    }

    func testAuthoritativeAbsenceRoutesPaired() async {
        let vault = makeVault()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in .absent }, saveStorage: {}
        )
        let model = FastVaultRoutingViewModel(refresher: refresher)
        let idle = idleExpectation(model)
        var route: Bool?
        model.resolve(vault) { route = $0 }
        await fulfillment(of: [idle], timeout: 2)
        XCTAssertEqual(route, false)
        XCTAssertFalse(model.hasError)
    }

    func testLocalServerShareRoutesPairedWithoutNetworking() {
        let vault = makeVault()
        vault.localPartyID = "server-fixture"
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in XCTFail("Local server share cannot use hosted route"); return .present },
            saveStorage: {}
        )
        let model = FastVaultRoutingViewModel(refresher: refresher)
        var route: Bool?
        model.resolve(vault) { route = $0 }
        XCTAssertEqual(route, false)
        XCTAssertFalse(model.isChecking)
    }
}
