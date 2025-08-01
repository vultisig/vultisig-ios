//
//  OutlinedDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-21.
//

import SwiftUI

struct OutlinedDisclaimer: View {
    @Environment(\.theme) var theme
    let text: String
    var alignment: TextAlignment = .leading

    var body: some View {
        content
    }
    
    var content: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(LinearGradient.primaryGradient)
                .font(.body14Menlo)
            
            Text(text)
                .font(theme.fonts.caption12)
                .foregroundColor(.neutral0)
                .lineSpacing(4)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(
            overlay
        )
    }
}

#Preview {
    OutlinedDisclaimer(text: "String")
}
