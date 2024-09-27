//
//  SettingsLanguageSelectionView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension SettingsLanguageSelectionView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "language")
            .padding(.bottom, 8)
    }
    
    var cells: some View {
        VStack(spacing: 16) {
            ForEach(SettingsLanguage.allCases, id: \.self) { language in
                Button {
                    handleSelection(language)
                } label: {
                    SettingSelectionCell(
                        title: language.rawValue,
                        isSelected: language==settingsViewModel.selectedLanguage,
                        description: language.description()
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
