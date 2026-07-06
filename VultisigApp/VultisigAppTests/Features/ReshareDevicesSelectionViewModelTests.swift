//
//  ReshareDevicesSelectionViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class ReshareDevicesSelectionViewModelTests: XCTestCase {

    private func makeViewModel(
        currentDeviceCount: Int,
        requiredActiveSigners: Int
    ) -> ReshareDevicesSelectionViewModel {
        ReshareDevicesSelectionViewModel(
            currentDeviceCount: currentDeviceCount,
            requiredActiveSigners: requiredActiveSigners
        )
    }

    // MARK: - Selection mapping

    func testSelectedDeviceCountMapsRiveIndexToDisplayedCount() {
        let viewModel = makeViewModel(currentDeviceCount: 3, requiredActiveSigners: 1)

        for (index, expectedCount) in [(0, 1), (1, 2), (2, 3), (3, 4)] {
            viewModel.selectedIndex = index
            XCTAssertEqual(viewModel.selectedDeviceCount, expectedCount)
        }
    }

    // MARK: - Threshold gate

    func testThresholdMetForAllCountsOnSmallVault() {
        // 2-of-3 style vault: required active signers is low enough that
        // every selectable count is allowed.
        let viewModel = makeViewModel(currentDeviceCount: 3, requiredActiveSigners: 1)

        for index in 0...3 {
            viewModel.selectedIndex = index
            XCTAssertTrue(viewModel.isThresholdMet, "index \(index) should be allowed")
        }
    }

    func testThresholdGateBlocksCountsBelowRequiredSigners() {
        // Five-signer vault requiring 3 active signers (the Figma example):
        // selecting 1 or 2 devices is blocked, 3 and 4+ are allowed.
        let viewModel = makeViewModel(currentDeviceCount: 5, requiredActiveSigners: 3)

        viewModel.selectedIndex = 0
        XCTAssertFalse(viewModel.isThresholdMet)
        viewModel.selectedIndex = 1
        XCTAssertFalse(viewModel.isThresholdMet)
        viewModel.selectedIndex = 2
        XCTAssertTrue(viewModel.isThresholdMet)
        viewModel.selectedIndex = 3
        XCTAssertTrue(viewModel.isThresholdMet)
    }

    // MARK: - Destination routing

    func testSingleDeviceRoutesToFastVaultPassword() {
        let viewModel = makeViewModel(currentDeviceCount: 2, requiredActiveSigners: 1)

        viewModel.selectedIndex = 0
        viewModel.isFastVaultEligible = false
        XCTAssertEqual(viewModel.destination, .fastVaultPassword(isExistingVault: false))

        viewModel.isFastVaultEligible = true
        XCTAssertEqual(viewModel.destination, .fastVaultPassword(isExistingVault: true))
    }

    func testMultiDeviceRoutesToPeerDiscoveryWithSelectedCount() {
        let viewModel = makeViewModel(currentDeviceCount: 2, requiredActiveSigners: 1)

        viewModel.selectedIndex = 1
        XCTAssertEqual(
            viewModel.destination,
            .peerDiscovery(setupType: .secure(numberOfDevices: 2))
        )

        viewModel.selectedIndex = 3
        XCTAssertEqual(
            viewModel.destination,
            .peerDiscovery(setupType: .secure(numberOfDevices: 4))
        )
    }

    // MARK: - Warning copy

    func testThresholdWarningTextEmbedsCurrentSelectedAndRequiredCounts() {
        let viewModel = makeViewModel(currentDeviceCount: 5, requiredActiveSigners: 3)
        viewModel.selectedIndex = 0

        let text = viewModel.thresholdWarningText
        XCTAssertTrue(text.contains("5"))
        XCTAssertTrue(text.contains("1"))
        XCTAssertTrue(text.contains("3"))
    }
}
