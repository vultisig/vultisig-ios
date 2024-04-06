//
//  SettingsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("settings", comment: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack {
                mainSection
                otherSection
            }
            .padding(15)
            .padding(.top, 30)
        }
    }
    
    var mainSection: some View {
        VStack(spacing: 16) {
            languageSelectionCell
            currencySelectionCell
            faqCell
        }
    }
    
    var otherSection: some View {
        VStack(spacing: 16) {
            getTitle("other")
            shareAppCell
        }
        .padding(.top, 24)
    }
    
    var languageSelectionCell: some View {
        NavigationLink {
            SettingsLanguageSelectionView()
        } label: {
            SettingCell(title: "language", icon: "globe", selection: settingsViewModel.selectedLanguage.rawValue)
        }
    }
    
    var currencySelectionCell: some View {
        NavigationLink {
            SettingsCurrencySelectionView()
        } label: {
            SettingCell(title: "currency", icon: "dollarsign.circle", selection: settingsViewModel.selectedCurrency.rawValue)
        }
    }
    
    var faqCell: some View {
        NavigationLink {
            SettingsFAQView()
        } label: {
            SettingCell(title: "faq", icon: "questionmark.circle")
        }
    }
    
    var shareAppCell: some View {
        // TODO: Update with app's url
        let link = URL(string: "https://www.google.com/")!
        
        return ShareLink(item: link) {
            SettingCell(title: "shareTheApp", icon: "square.and.arrow.up")
        }
    }
    
    private func getTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
}
