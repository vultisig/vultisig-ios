//
//  SettingsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsView: View {
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
            mainSection
        }
    }
    
    var mainSection: some View {
        VStack(spacing: 16) {
            
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
}
