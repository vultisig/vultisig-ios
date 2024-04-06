//
//  SettingsCurrencySelectionView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsCurrencySelectionView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("currency", comment: "Currency"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
                        isSelected: currency==settingsViewModel.selectedCurrency
                    )
                }
            }
        }
        .padding(15)
        .padding(.top, 30)
    }
    
    private func handleSelection(_ currency: SettingsCurrency) {
        settingsViewModel.selectedCurrency = currency
        dismiss()
    }
}

#Preview {
    SettingsCurrencySelectionView()
        .environmentObject(SettingsViewModel())
}
