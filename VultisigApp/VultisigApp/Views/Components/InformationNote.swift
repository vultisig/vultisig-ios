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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgAlert.opacity(0.35))
        .cornerRadius(12)
        .overlay(
            overlay
        )
        .padding(1)
    }

    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(Theme.colors.bgAlert)
    }

    var text: some View {
        if message == nil {
            Text(NSLocalizedString("joinKeygenConnectionDisclaimer", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
        } else {
            Text(message ?? "")
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
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
