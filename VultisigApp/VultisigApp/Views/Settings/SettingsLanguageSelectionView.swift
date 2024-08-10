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
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("language", comment: "Language"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
#endif
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("languageChangeTitle", comment: "Language Changed")),
                message: Text(NSLocalizedString("restart", comment: "Please restart the app to apply the new language settings.")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "OK")))
            )
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "language")
            .padding(.bottom, 8)
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
#if os(macOS)
        .padding(.horizontal, 25)
#endif
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
