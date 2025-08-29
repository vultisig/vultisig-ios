//
//  SettingsFAQView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsFAQView: View {
    var body: some View {
        Screen(title: "faq".localized, edgeInsets: ScreenEdgeInsets(bottom: 0)) {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: .zero) {
                        ForEach(SettingsOptionsStore.FAQData, id: \.question) { faq in
                            SettingFAQCell(question: faq.question, answer: faq.answer)
                            GradientListSeparator()
                                .showIf(faq.question != SettingsOptionsStore.FAQData.last?.question)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsFAQView()
}
