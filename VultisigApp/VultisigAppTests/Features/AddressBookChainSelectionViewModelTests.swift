//
//  AddressBookChainSelectionViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class AddressBookChainSelectionViewModelTests: XCTestCase {

    private func filtered(_ search: String) -> [AddressBookChainType] {
        let viewModel = AddressBookChainSelectionViewModel(vaultChains: [TokensStore.ethDPI, TokensStore.ton])
        viewModel.setup()
        viewModel.searchText = search
        return viewModel.filteredChains
    }

    private func isEVM(_ type: AddressBookChainType) -> Bool {
        if case .evm = type { return true }
        return false
    }

    func test_nonEVMChainNameDoesNotMatchTheEVMOption() {
        let result = filtered("gram")
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.contains(where: isEVM))
    }

    func test_evmChainNameStillMatchesTheEVMOption() {
        XCTAssertTrue(filtered("eth").contains(where: isEVM))
    }
}
