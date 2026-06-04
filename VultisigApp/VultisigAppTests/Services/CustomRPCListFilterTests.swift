//
//  CustomRPCListFilterTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Exercises the pure name/ticker filter on `CustomRPCListViewModel.filteredRows`.
/// Filtering depends only on `CustomRPCSupportedChains.all` and `searchText`, so
/// no override state is needed.
@MainActor
final class CustomRPCListFilterTests: XCTestCase {

    private func makeViewModel() -> CustomRPCListViewModel {
        let viewModel = CustomRPCListViewModel()
        viewModel.reload()
        return viewModel
    }

    func test_emptySearch_returnsAllRows() {
        let viewModel = makeViewModel()
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredRows.count, CustomRPCSupportedChains.all.count)
    }

    func test_whitespaceSearch_returnsAllRows() {
        let viewModel = makeViewModel()
        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredRows.count, CustomRPCSupportedChains.all.count)
    }

    func test_nameMatch_isCaseInsensitive() {
        let viewModel = makeViewModel()
        viewModel.searchText = "eth"
        XCTAssertTrue(viewModel.filteredRows.contains { $0.chain == .ethereum })

        viewModel.searchText = "ETHEREUM"
        XCTAssertTrue(viewModel.filteredRows.contains { $0.chain == .ethereum })
    }

    func test_tickerMatch_findsChainWhoseNameDoesNotContainQuery() {
        let viewModel = makeViewModel()
        // "XRP" is Ripple's ticker; the name "Ripple" does not contain "xrp".
        viewModel.searchText = "xrp"
        let matches = viewModel.filteredRows
        XCTAssertTrue(matches.contains { $0.chain == .ripple })
        XCTAssertFalse("Ripple".localizedCaseInsensitiveContains("xrp"))
    }

    func test_tickerMatch_isCaseInsensitive() {
        let viewModel = makeViewModel()
        // BSC's ticker is "BNB"; its name "BSC" does not contain "bnb".
        viewModel.searchText = "bnb"
        XCTAssertTrue(viewModel.filteredRows.contains { $0.chain == .bscChain })
    }

    func test_noMatch_returnsEmpty() {
        let viewModel = makeViewModel()
        viewModel.searchText = "definitely-not-a-chain"
        XCTAssertTrue(viewModel.filteredRows.isEmpty)
    }

    func test_searchTrimsSurroundingWhitespace() {
        let viewModel = makeViewModel()
        viewModel.searchText = "  ethereum  "
        XCTAssertTrue(viewModel.filteredRows.contains { $0.chain == .ethereum })
    }
}
