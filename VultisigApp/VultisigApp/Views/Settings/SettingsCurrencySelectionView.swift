//
//  SettingsCurrencySelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsCurrencySelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State var isLoading = false
    
    var body: some View {
        Screen(title: "currency".localized) {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: .zero) {
                        ForEach(SettingsCurrency.allCases, id: \.self) { currency in
                            Button {
                                handleSelection(currency)
                            } label: {
                                SettingSelectionCell(
                                    title: currency.rawValue,
                                    isSelected: currency.rawValue == settingsViewModel.selectedCurrency.rawValue
                                )
                            }
                        }
                    }
                }
            }
        }
        .overlay(isLoading ? Loader() : nil)
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
}

#Preview {
    SettingsCurrencySelectionView()
}
