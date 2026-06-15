//
//  CustomRPCSelectChainFilterTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Exercises the pure name/ticker filter on
/// `CustomRPCSelectChainViewModel.filteredChains`. Filtering depends only on
/// `CustomRPCSupportedChains.all` and `searchText`, so no override state is
/// needed.
@MainActor
final class CustomRPCSelectChainFilterTests: XCTestCase {

    private func makeViewModel() -> CustomRPCSelectChainViewModel {
        CustomRPCSelectChainViewModel()
    }

    func test_emptySearch_returnsAllChains() {
        let viewModel = makeViewModel()
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredChains.count, CustomRPCSupportedChains.all.count)
    }

    func test_whitespaceSearch_returnsAllChains() {
        let viewModel = makeViewModel()
        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredChains.count, CustomRPCSupportedChains.all.count)
    }

    func test_nameMatch_isCaseInsensitive() {
        let viewModel = makeViewModel()
        viewModel.searchText = "eth"
        XCTAssertTrue(viewModel.filteredChains.contains(.ethereum))

        viewModel.searchText = "ETHEREUM"
        XCTAssertTrue(viewModel.filteredChains.contains(.ethereum))
    }

    func test_tickerMatch_findsChainWhoseNameDoesNotContainQuery() {
        let viewModel = makeViewModel()
        // "XRP" is Ripple's ticker; the name "Ripple" does not contain "xrp".
        viewModel.searchText = "xrp"
        XCTAssertTrue(viewModel.filteredChains.contains(.ripple))
        XCTAssertFalse("Ripple".localizedCaseInsensitiveContains("xrp"))
    }

    func test_tickerMatch_isCaseInsensitive() {
        let viewModel = makeViewModel()
        // BSC's ticker is "BNB"; its name "BSC" does not contain "bnb".
        viewModel.searchText = "bnb"
        XCTAssertTrue(viewModel.filteredChains.contains(.bscChain))
    }

    func test_noMatch_returnsEmpty() {
        let viewModel = makeViewModel()
        viewModel.searchText = "definitely-not-a-chain"
        XCTAssertTrue(viewModel.filteredChains.isEmpty)
    }

    func test_searchTrimsSurroundingWhitespace() {
        let viewModel = makeViewModel()
        viewModel.searchText = "  ethereum  "
        XCTAssertTrue(viewModel.filteredChains.contains(.ethereum))
    }
}
