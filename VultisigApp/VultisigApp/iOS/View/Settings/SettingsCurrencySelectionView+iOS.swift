//
//  SettingsCurrencySelectionView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension SettingsCurrencySelectionView {
    var content: some View {
        ZStack {
            Background()
            main
            
            if isLoading {
                Loader()
            }
        }
        .navigationTitle(NSLocalizedString("currency", comment: "Currency"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
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
}
#endif
