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

    func onLoad() {
        let locale = Locale(identifier: "en_US")
        currencies = SettingsCurrency.allCases.map { currency in
            let symbol = FiatFormatLocale.currencyFormatter(for: currency.rawValue).currencySymbol ?? ""
            return SettingsCurrencyViewModel(
                currency: currency,
                description: "\(locale.localizedString(forCurrencyCode: currency.rawValue) ?? "") (\(symbol))"
            )
        }
    }
}

#Preview {
    SettingsCurrencySelectionView()
        .environmentObject(AppViewModel())
}
