//
//  SettingsLanguageSelectionView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsLanguageSelectionView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
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
    }
    
    private func handleSelection(_ language: SettingsLanguage) {
        settingsViewModel.selectedLanguage = language
        dismiss()
    }
}

#Preview {
    SettingsLanguageSelectionView()
        .environmentObject(SettingsViewModel())
}
