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

    func balanceText(for vaults: [Vault]) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }

        return vaults
            .map(\.coins.totalBalanceInFiatDecimal)
            .reduce(0, +)
            .formatToFiat(includeCurrencySymbol: true)
    }

    func balanceText(for vault: Vault?) -> String {
        guard !hideVaultBalance else {
            return String.hideBalanceText
        }

        return vault?.coins.totalBalanceInFiatString ?? ""
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
