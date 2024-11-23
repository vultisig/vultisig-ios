//
//  SettingsFAQView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension SettingsFAQView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("faq", comment: "FAQ"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
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
#endif
