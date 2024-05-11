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
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("language", comment: "Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
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
    
    var view: some View {
        ScrollView {
            cells
        }
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
    
    private func handleSelection(_ language: SettingsLanguage) {
        settingsViewModel.selectedLanguage = language
        showAlert = true
    }
}

#Preview {
    SettingsLanguageSelectionView()
        .environmentObject(SettingsViewModel())
}
