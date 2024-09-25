//
//  SettingsFAQView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension SettingsFAQView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "faq")
            .padding(.bottom, 8)
    }
    
    var cells: some View {
        VStack(spacing: 16) {
            ForEach(SettingsOptionsStore.FAQData, id: \.question) { faq in
                SettingFAQCell(question: faq.question, answer: faq.answer)
            }
        }
        .padding(15)
        .padding(.top, 30)
        .padding(.horizontal, 25)
    }
}
#endif
