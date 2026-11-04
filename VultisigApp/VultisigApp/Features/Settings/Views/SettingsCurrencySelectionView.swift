//
//  SettingsCurrencySelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

private struct SettingsCurrencyViewModel {
    let currency: SettingsCurrency
    let description: String
}

struct SettingsCurrencySelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var currencies: [SettingsCurrencyViewModel] = []

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: .zero) {
                    ForEach(Array(currencies.enumerated()), id: \.element.currency) { index, viewModel in
                        Button {
                            handleSelection(viewModel.currency)
                        } label: {
                            SettingSelectionCell(
                                title: viewModel.description,
                                isSelected: viewModel.currency.rawValue == settingsViewModel.selectedCurrency.rawValue,
                                style: .highlighted(title: .bodyS)
                            )
                        }
                        .commonListItemContainer(index: index, itemsCount: currencies.count, style: .flush)
                    }
                }
                .commonListContainer(style: .flush)
            }
        }
        .screenTitle("currency".localized)
        .screenEdgeInsets(ScreenEdgeInsets(top: CommonListContainer.flushScreenTopInset, bottom: 0))
        .onLoad(perform: onLoad)
    }

    func handleSelection(_ currency: SettingsCurrency) {
        settingsViewModel.selectedCurrency = currency

        // Only the display currency changed — refresh rates and relabel fiat from
        // cache. No per-coin balance RPCs, no Cardano discovery.
        if let currentVault = appViewModel.selectedVault {
            Task {
                await BalanceService.shared.refreshRates(vault: currentVault)
            }
        }
        dismiss()
    }

    /// The design lists the Swiss Franc ahead of the Pound.
    private var displayOrder: [SettingsCurrency] {
        var order = SettingsCurrency.allCases
        if let pound = order.firstIndex(of: .GBP), let franc = order.firstIndex(of: .CHF) {
            order.swapAt(pound, franc)
        }
        return order
    }

    func onLoad() {
        let formatter = NumberFormatter()
        let locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        // Unambiguous in every device region: US$, JP¥ and CA$ rather than a bare $ or ¥.
        formatter.locale = Locale(identifier: "en_GB")
        currencies = displayOrder.map { currency in
            formatter.currencyCode = currency.rawValue
            return SettingsCurrencyViewModel(
                currency: currency,
                description: "\(locale.localizedString(forCurrencyCode: currency.rawValue) ?? "") (\(formatter.currencySymbol ?? ""))"
            )
        }
    }
}

#Preview {
    SettingsCurrencySelectionView()
        .environmentObject(AppViewModel())
}
