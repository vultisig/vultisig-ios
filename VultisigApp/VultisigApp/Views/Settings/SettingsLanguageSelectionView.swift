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

    var body: some View {
        Screen(title: "language".localized, edgeInsets: ScreenEdgeInsets(bottom: 0)) {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: .zero) {
                        ForEach(SettingsLanguage.allCases, id: \.self) { language in
                            Button {
                                handleSelection(language)
                            } label: {
                                SettingSelectionCell(
                                    title: language.rawValue,
                                    isSelected: language==settingsViewModel.selectedLanguage,
                                    description: language.description(),
                                    showSeparator: language != SettingsLanguage.allCases.last
                                )
                            }
                        }
                    }
                }
            }
        }
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
