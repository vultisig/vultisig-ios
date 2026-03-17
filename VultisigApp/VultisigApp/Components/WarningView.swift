//
//  WarningView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.10.2024.
//

import SwiftUI

struct WarningView: View {
    let text: String

    var body: some View {
        components
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(Theme.colors.alertError.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.alertError, lineWidth: 1)
            )
    }

    var components: some View {
        HStack(spacing: 24) {
            icon
            title
            icon
        }
    }

    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(Theme.fonts.title2)
            .foregroundColor(Theme.colors.alertError)
    }

    var title: some View {
        Text(text)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    WarningView(text: "Backup your vault on every device individually!")
}
