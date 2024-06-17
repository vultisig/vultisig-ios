//
//  SettingsFAQView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsFAQView: View {
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("faq", comment: "FAQ"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
#endif
    }
    
    var view: some View {
        ScrollView {
            cells
        }
    }
    
    var cells: some View {
        VStack(spacing: 16) {
            ForEach(SettingsOptionsStore.FAQData, id: \.question) { faq in
                SettingFAQCell(question: faq.question, answer: faq.answer)
            }
        }
        .padding(15)
        .padding(.top, 30)
    }
}

#Preview {
    SettingsFAQView()
}
