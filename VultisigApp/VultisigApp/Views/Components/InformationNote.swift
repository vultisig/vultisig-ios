//
//  InformationNote.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI

struct InformationNote: View {
    @State var message: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            icon
            text
        }
        .padding(12)
        .background(Color.warningYellow.opacity(0.35))
        .cornerRadius(12)
        .overlay(
            overlay
        )
    }
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(Color.warningYellow)
    }
    
    var text: some View {
        if message == nil {
            Text(NSLocalizedString("informationNote", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body12MontserratSemiBold)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
        } else {
            Text(message ?? "")
                .foregroundColor(.neutral0)
                .font(.body12MontserratSemiBold)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
        }
    }
}

#Preview {
    ZStack {
        Background()
        InformationNote()
    }
}
