//
//  PrimaryButtonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButtonView: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?
    let isLoading: Bool
    let paddingLeading: CGFloat
    let reserveTrailingIconSpace: Bool

    init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        isLoading: Bool = false,
        paddingLeading: CGFloat = 0,
        reserveTrailingIconSpace: Bool = false
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.isLoading = isLoading
        self.paddingLeading = paddingLeading
        self.reserveTrailingIconSpace = reserveTrailingIconSpace
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            if let leadingIcon {
                Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15)
            }

            Text(NSLocalizedString(title, comment: "Button Text"))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, paddingLeading)

            if let trailingIcon {
                Icon(named: trailingIcon, color: Theme.colors.textPrimary, size: 15)
            } else if reserveTrailingIconSpace {
                // Reserve space for trailing icon to keep content centered
                Icon(named: "check", color: .clear, size: 15)
            }
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PrimaryButtonView(title: "Next")
}
