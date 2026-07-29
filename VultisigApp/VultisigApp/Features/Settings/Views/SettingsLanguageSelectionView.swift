//
//  SettingsLanguageSelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsLanguageSelectionView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showAlert = false
    @Environment(\.dismiss) var dismiss

    private var languages: [SettingsLanguage] {
        SettingsLanguage.allCases
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: .zero) {
                    ForEach(Array(languages.enumerated()), id: \.element) { index, language in
                        Button {
                            handleSelection(language)
                        } label: {
                            SettingSelectionCell(
                                title: language.rawValue,
                                isSelected: language == settingsViewModel.selectedLanguage,
                                description: language.description()
                            )
                        }
                        .commonListItemContainer(index: index, itemsCount: languages.count)
                    }
                }
                .commonListContainer()
            }
        }
        .screenTitle("language".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("languageChangeTitle", comment: "Language Changed")),
                message: Text(NSLocalizedString("restart", comment: "Please restart the app to apply the new language settings.")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "OK")))
            )
        }
    }

    func handleSelection(_ language: SettingsLanguage) {
        settingsViewModel.selectedLanguage = language
        showAlert = true
    }
}

#Preview {
    SettingsLanguageSelectionView()
        .environmentObject(SettingsViewModel())
}
