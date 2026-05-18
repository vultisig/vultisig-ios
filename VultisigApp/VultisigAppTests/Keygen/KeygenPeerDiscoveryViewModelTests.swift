//
//  KeygenPeerDiscoveryViewModelTests.swift
//  VultisigAppTests
//
//  Locks in the auto-kickoff behavior for fixed-device secure-vault flows
//  (2/2, 3/3) and the manual-Continue requirement for 4+ device flows.
//  Mirrors the Windows `AutoStartKeygen` component reference cited in
//  vultisig-ios#4374.
//

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
}
