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
                SettingsSectionContainerView {
                    VStack(spacing: .zero) {
                        ForEach(currencies, id: \.currency) { viewModel in
                            Button {
                                handleSelection(viewModel.currency)
                            } label: {
                                SettingSelectionCell(
                                    title: viewModel.description,
                                    isSelected: viewModel.currency.rawValue == settingsViewModel.selectedCurrency.rawValue,
                                    showSeparator: viewModel.currency != SettingsCurrency.allCases.last
                                )
                            }
                        }
                    }
                }
            }
        }
        .screenTitle("currency".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
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
        let formatter = NumberFormatter()
        let locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        currencies = SettingsCurrency.allCases.map { currency in
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
