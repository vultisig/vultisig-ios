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
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("faq", comment: "FAQ"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
#endif
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
        GeneralMacHeader(title: "faq")
            .padding(.bottom, 8)
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
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }
}

#Preview {
    SettingsFAQView()
}
