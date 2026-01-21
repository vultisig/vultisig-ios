//
//  SwiftUIView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct ErrorMessage: View {
    let text: String
    var width: CGFloat = 200

    var body: some View {
        VStack(spacing: 24) {
            logo
            title
        }
    }

    var logo: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(Theme.fonts.title2)
            .foregroundColor(Theme.colors.alertWarning)
    }

    var title: some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.alertWarning)
            .frame(maxWidth: width)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        ErrorMessage(text: "signingErrorTryAgain")
    }
}
