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
        ZStack {
            Background()
            view
            
            if isLoading {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("currency", comment: "Currency"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }

    }
    
    var view: some View {
        ScrollView {
            cells
        }
    }
    
    var cells: some View {
        VStack(spacing: 16) {
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
        .padding(15)
        .padding(.top, 30)
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }
    
    private func handleSelection(_ currency: SettingsCurrency) {
        isLoading = true
        settingsViewModel.selectedCurrency = currency
        
        Task{
            if let currentVault = ApplicationState.shared.currentVault {
                await CryptoPriceService.shared.clearCache()
                await BalanceService.shared.clearCache()
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
