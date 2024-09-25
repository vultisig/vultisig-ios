//
//  SettingsLanguageSelectionView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension SettingsLanguageSelectionView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("language", comment: "Language"))
    }
    
    var main: some View {
        view
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
    }
}
#endif
