import XCTest
@testable import VultisigApp

@MainActor
final class FastVaultRoutingTests: XCTestCase {
    private var store: TestContextToken?

    override func setUp() async throws {
        store = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(store)
        store = nil
    }

    private func makeVault() -> Vault {
        let vault = TestStore.makeVault(pubKey: UUID().uuidString)
        vault.localPartyID = "device"
        vault.signers = ["device", "server-fixture"]
        return vault
    }

    func testRoutingReusesFreshBackgroundConfirmation() async {
        let vault = makeVault()
        var calls = 0
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in calls += 1; return .present }, saveStorage: {}
        )
        await refresher.refreshIfStale(vault)
        let presence = await refresher.presenceForRouting(vault)
        XCTAssertEqual(presence, .present)
        XCTAssertEqual(calls, 1)
    }

    func testUnknownInvalidatesRoutingConfirmationAndRetryRecovers() async {
        let vault = makeVault()
        var result: FastVaultPresence = .present
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in result }, saveStorage: {}
        )
        await refresher.refresh(vault)
        result = .unknown(.requestFailed)
        await refresher.refresh(vault)
        XCTAssertNil(refresher.confirmedPresenceForRouting(vault))
        let failed = await refresher.presenceForRouting(vault)
        XCTAssertEqual(failed, .unknown(.requestFailed))
        XCTAssertTrue(vault.offersFastSigning)
        result = .present
        let retried = await refresher.presenceForRouting(vault)
        XCTAssertEqual(retried, .present)
    }

    func testCancelledRoutingCallerDoesNotConsumeLateSuccess() async {
        let vault = makeVault()
        var release: CheckedContinuation<FastVaultPresence, Never>?
        let started = expectation(description: "lookup starts")
        let refresher = FastVaultEligibilityRefresher(checkEligibility: { _ in
            await withCheckedContinuation { release = $0; started.fulfill() }
        }, saveStorage: {})
        let request = Task { await refresher.presenceForRouting(vault) }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        release?.resume(returning: .present)
        let result = await request.value
        XCTAssertEqual(result, .unknown(.cancelled))
        XCTAssertEqual(refresher.confirmedPresenceForRouting(vault), .present)
    }

    func testSecureAndLocalServerSharesNeedNoLookup() async {
        let vault = makeVault()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in XCTFail("No hosted lookup expected"); return .present }, saveStorage: {}
        )
        vault.localPartyID = "server-fixture"
        let localServerPresence = await refresher.presenceForRouting(vault)
        XCTAssertEqual(localServerPresence, .absent)
        vault.localPartyID = "device"
        vault.signers = ["device", "other"]
        let securePresence = await refresher.presenceForRouting(vault)
        XCTAssertEqual(securePresence, .absent)
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

}
