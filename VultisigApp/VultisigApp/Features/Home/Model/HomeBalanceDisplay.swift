//
//  HomeBalanceDisplay.swift
//  VultisigApp
//

import Foundation

/// What the home header's balance means. App-wide, chosen in Settings.
enum HomeBalanceDisplay: String, CaseIterable, Identifiable {
    /// Each tab shows its own total: wallet holdings on Wallet, positions on DeFi.
    case separate
    /// Both tabs show wallet holdings plus DeFi positions.
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .separate: "homeDisplaySeparateTitle".localized
        case .combined: "homeDisplayCombinedTitle".localized
        }
    }

    var description: String {
        switch self {
        case .separate: "homeDisplaySeparateDescription".localized
        case .combined: "homeDisplayCombinedDescription".localized
        }
    }

    /// Combined adds only the DeFi value the wallet total does not already hold.
    func total(for tab: HomeTab, wallet: Decimal, defi: DefiTotals) -> Decimal {
        switch self {
        case .combined: wallet + defi.notInWallet
        case .separate: tab == .defi ? defi.total : wallet
        }
    }
}
