//
//  SettingsFAQView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsFAQView: View {
    private var faqs: [(question: String, answer: String)] {
        SettingsOptionsStore.FAQData
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: .zero) {
                    ForEach(Array(faqs.enumerated()), id: \.element.question) { index, faq in
                        SettingFAQCell(question: faq.question, answer: faq.answer)
                            .commonListItemContainer(index: index, itemsCount: faqs.count)
                    }
                }
                .commonListContainer()
            }
        }
        .screenTitle("faq".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }
}

#Preview {
    SettingsFAQView()
}
