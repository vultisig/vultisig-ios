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

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("currency", comment: "Currency"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
    }
    
    private func handleSelection(_ currency: SettingsCurrency) {
        settingsViewModel.selectedCurrency = currency
        dismiss()
    }
}

#Preview {
    SettingsCurrencySelectionView()
}
