//
//  SheetHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct SheetHeaderView: View {
    let title: String
    @Binding var isPresented: Bool
    
    var body: some View {
        HStack {
            backButton
            Spacer()
            titleView
            Spacer()
            backButton
                .opacity(0)
        }
    }
    
    @ViewBuilder
    var backButton: some View {
        #if os(macOS)
            Button {
                isPresented = false
            } label: {
                NavigationBlankBackButton()
            }
        #endif
    }
    
    var titleView: some View {
        Text(title)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
}
