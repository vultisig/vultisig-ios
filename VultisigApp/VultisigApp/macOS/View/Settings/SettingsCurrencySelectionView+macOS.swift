//
//  SettingsCurrencySelectionView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
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
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "currency")
            .padding(.bottom, 8)
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
        .padding(.horizontal, 25)
    }
}
#endif
