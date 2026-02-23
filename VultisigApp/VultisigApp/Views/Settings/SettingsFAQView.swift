//
//  SettingsFAQView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsFAQView: View {
    var body: some View {
        Screen {
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
        .screenTitle("faq".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }
}

#Preview {
    SettingsFAQView()
}
