//
//  HomeViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

class HomeViewModel: ObservableObject {
    @AppStorage("showVaultBalance") var hideVaultBalance: Bool = false
    @AppStorage("homeBalanceDisplay") var balanceDisplay: HomeBalanceDisplay = .separate
    @AppStorage("hasSeenHomeSwipeHint") var hasSeenSwipeHint: Bool = false

    @Published var filteredVaults: [Vault] = []

    @Published var showAlert: Bool = false

    @Published var shouldShowScanner: Bool = false

    @MainActor
    func balanceText(for vaults: [Vault]) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }

        return vaults
            .map(totalBalance(for:))
            .reduce(0, +)
            .formatToFiat(includeCurrencySymbol: true)
    }

    @MainActor
    func balanceText(for vault: Vault?) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }
        guard let vault else { return "" }

        return totalBalance(for: vault).formatToFiat(includeCurrencySymbol: true)
    }

    /// The wallet total, plus the DeFi value it does not already hold when the display is combined.
    @MainActor
    private func totalBalance(for vault: Vault) -> Decimal {
        let wallet = vault.coins.totalBalanceInFiatDecimal
        guard balanceDisplay == .combined else { return wallet }

        return balanceDisplay.total(
            for: .wallet,
            wallet: wallet,
            defi: DefiBalanceService().totals(for: vault.defiChains, vault: vault)
        )
    }

    func filterVaults(vaults: [Vault], folders: [Folder]) {
        filteredVaults = getFilteredVaults(vaults: vaults, folders: folders)
    }

    func getFilteredVaults(vaults: [Vault], folders: [Folder]) -> [Vault] {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })

        return vaults.filter({ vault in
            !vaultNames.contains(vault.name)
        })
    }
}
