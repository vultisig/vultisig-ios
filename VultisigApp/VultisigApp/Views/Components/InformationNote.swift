//
//  InformationNote.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI

struct InformationNote: View {
    var body: some View {
        HStack(spacing: 12) {
            icon
            text
        }
        .padding(12)
        .background(Color.warningYellow.opacity(0.35))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
            #if os(iOS)
                .stroke(Color.warningYellow, lineWidth: 1)
            #elseif os(macOS)
                .stroke(Color.warningYellow, lineWidth: 2)
            #endif
        )
    }
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(Color.warningYellow)
    }
    
    var text: some View {
        Text(NSLocalizedString("informationNote", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body12MontserratSemiBold)
            .lineSpacing(8)
            .multilineTextAlignment(.leading)
    }
}

#Preview {
    ZStack {
        Background()
        InformationNote()
    }
}
