//
//  KeygenPeerDiscoveryViewModelTests.swift
//  VultisigAppTests
//
//  Locks in the auto-kickoff behavior for fixed-device secure-vault flows
//  (2/2, 3/3) and the manual-Continue requirement for 4+ device flows.
//  Mirrors the Windows `AutoStartKeygen` component reference cited in
//  vultisig-ios#4374.
//

import Combine
import XCTest
@testable import VultisigApp

@MainActor
final class KeygenPeerDiscoveryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        tssType: TssType = .Keygen,
        status: PeerDiscoveryStatus = .WaitingForDevices,
        selectionCount: Int = 1
    ) -> KeygenPeerDiscoveryViewModel {
        let vm = KeygenPeerDiscoveryViewModel()
        vm.tssType = tssType
        vm.status = status
        vm.localPartyID = "iPhone-Local"
        vm.selections = []
        vm.selections.insert(vm.localPartyID)
        for index in 1..<selectionCount {
            vm.selections.insert("Peer-\(index)")
        }
        return vm
    }

    // MARK: - Fixed-device auto-start (2/2 and 3/3)

    func testShouldAutoStartTwoOfTwoWhenPartnerConnected() {
        let vm = makeVM(selectionCount: 2)
        XCTAssertTrue(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    func testShouldNotAutoStartTwoOfTwoWhilePartnerStillConnecting() {
        let vm = makeVM(selectionCount: 1)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    func testShouldAutoStartThreeOfThreeWhenAllPeersConnected() {
        let vm = makeVM(selectionCount: 3)
        XCTAssertTrue(vm.shouldAutoStartKeygen(totalDeviceCount: 3))
    }

    func testShouldNotAutoStartThreeOfThreeWithOnlyOnePeer() {
        let vm = makeVM(selectionCount: 2)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 3))
    }

    // MARK: - 4+ device flows always require manual Continue

    func testShouldNotAutoStartFourDeviceVaultEvenAtThreshold() {
        let vm = makeVM(selectionCount: 4)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 4))
    }

    func testShouldNotAutoStartFiveDeviceVaultEvenAtThreshold() {
        let vm = makeVM(selectionCount: 5)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 5))
    }

    // MARK: - Reshare never auto-starts

    func testShouldNotAutoStartReshareEvenWhenAtFixedDeviceThreshold() {
        let vm = makeVM(tssType: .Reshare, selectionCount: 2)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    func testShouldNotAutoStartReshareThreeOfThree() {
        let vm = makeVM(tssType: .Reshare, selectionCount: 3)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 3))
    }

    // MARK: - Status guard

    func testShouldNotAutoStartWhenKeygenAlreadyInProgress() {
        let vm = makeVM(status: .Keygen, selectionCount: 2)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    func testShouldNotAutoStartAfterFailure() {
        let vm = makeVM(status: .Failure, selectionCount: 2)
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    // MARK: - Edge cases

    func testShouldAutoStartWhenMorePeersJoinedThanRequired() {
        // 2/2 vault but somehow three peers are in the selection set. The
        // threshold is "met or exceeded" — auto-start fires regardless.
        let vm = makeVM(selectionCount: 3)
        XCTAssertTrue(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    func testShouldNotAutoStartWithZeroSelections() {
        // Edge case: localPartyID is normally inserted into `selections` at
        // init. If something clears the set, auto-start must not fire.
        let vm = makeVM(selectionCount: 1)
        vm.selections.removeAll()
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
    }

    // MARK: - Kickoff

    private func makeKickoffVM(http: KickoffHTTPClient) -> KeygenPeerDiscoveryViewModel {
        let vm = KeygenPeerDiscoveryViewModel(httpClient: http)
        vm.localPartyID = "iPhone-Local"
        vm.sessionID = "session-1"
        vm.serverAddr = "https://relay.invalid"
        vm.selections = ["Peer-1", "iPhone-Local"]
        return vm
    }

    private func waitForKickoff(_ vm: KeygenPeerDiscoveryViewModel) async {
        for _ in 0..<500 where vm.isStartingKeygen {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStartKeygenAwaitsTheKickoffThenEntersKeygen() async {
        let http = KickoffHTTPClient()
        let vm = makeKickoffVM(http: http)

        vm.startKeygen()
        XCTAssertTrue(vm.isStartingKeygen)
        XCTAssertEqual(vm.status, .WaitingForDevices)
        await waitForKickoff(vm)

        XCTAssertEqual(vm.status, .Keygen)
        XCTAssertFalse(vm.isStartingKeygen)
        XCTAssertEqual(vm.keygenCommittee.first, "iPhone-Local")
        XCTAssertEqual(http.kickoffs.count, 1)
        XCTAssertEqual(http.kickoffs.first?.sessionID, "session-1")
        XCTAssertEqual(http.kickoffs.first?.participants, vm.keygenCommittee)
    }

    func testKickoffFailureSurfacesAnErrorInsteadOfStartingKeygen() async {
        let http = KickoffHTTPClient()
        http.result = .failure(HTTPError.statusCode(500, nil))
        let vm = makeKickoffVM(http: http)
        var statuses: [PeerDiscoveryStatus] = []
        let cancellable = vm.$status.sink { statuses.append($0) }
        defer { cancellable.cancel() }

        vm.startKeygen()
        await waitForKickoff(vm)

        XCTAssertEqual(vm.status, .Failure)
        XCTAssertEqual(vm.errorMessage, "keygenKickoffFailed".localized)
        XCTAssertFalse(vm.isStartingKeygen)
        XCTAssertFalse(statuses.contains(.Keygen))
    }

    func testSecondStartWhileInFlightSendsASingleKickoff() async {
        let http = KickoffHTTPClient()
        let vm = makeKickoffVM(http: http)

        vm.startKeygen()
        vm.startKeygen()
        await waitForKickoff(vm)

        XCTAssertEqual(http.kickoffs.count, 1)
        XCTAssertEqual(vm.status, .Keygen)
    }

    func testShouldNotAutoStartWhileTheKickoffIsInFlight() async {
        let http = KickoffHTTPClient()
        http.delay = .milliseconds(200)
        let vm = makeKickoffVM(http: http)

        vm.startKeygen()
        XCTAssertFalse(vm.shouldAutoStartKeygen(totalDeviceCount: 2))
        await waitForKickoff(vm)

        XCTAssertEqual(vm.status, .Keygen)
    }
}

private final class KickoffHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    struct Kickoff {
        let sessionID: String
        let participants: [String]
    }

    var result: Result<Void, Error> = .success(())
    var delay: Duration = .zero
    private(set) var kickoffs: [Kickoff] = []

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        if let relay = target as? RelayServerAPI, case .startSession(let sessionID, let body) = relay.endpoint {
            let participants = (try? JSONDecoder().decode([String].self, from: body)) ?? []
            kickoffs.append(Kickoff(sessionID: sessionID, participants: participants))
        }
        if delay > .zero {
            try await Task.sleep(for: delay)
        } else {
            await Task.yield()
        }
        try result.get()
        let url = URL(string: "https://relay.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(), response: response)
    }
}
