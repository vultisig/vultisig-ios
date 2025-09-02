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
    
    @State private var currencies: [SettingsCurrencyViewModel] = []
    @State var isLoading = false
    
    var body: some View {
        Screen(title: "currency".localized, edgeInsets: ScreenEdgeInsets(bottom: 0)) {
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
        .overlay(isLoading ? Loader() : nil)
        .onLoad(perform: onLoad)
    }
    
    func handleSelection(_ currency: SettingsCurrency) {
        isLoading = true
        settingsViewModel.selectedCurrency = currency
        
        Task {
            if let currentVault = ApplicationState.shared.currentVault {
                await BalanceService.shared.updateBalances(vault: currentVault)
                dismiss()
                isLoading = false
            }
        }
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
}
