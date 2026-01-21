//
//  SendCryptoTransactionDetailsRow.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/07/2025.
//

import SwiftUI

struct SendCryptoTransactionDetailsRow<AccessoryView: View>: View {
    let title: String
    let description: String
    let secondaryDescription: String?
    let bracketValue: String?
    let icon: String?
    let accessoryView: (() -> AccessoryView)

    init(
        title: String,
        description: String,
        secondaryDescription: String? = nil,
        bracketValue: String? = nil,
        icon: String? = nil,
        @ViewBuilder accessoryView: @escaping () -> AccessoryView
    ) {
        self.title = title
        self.description = description
        self.secondaryDescription = secondaryDescription
        self.bracketValue = bracketValue
        self.icon = icon
        self.accessoryView = accessoryView
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(spacing: 2) {
                Text(NSLocalizedString(title, comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let icon {
                    Image(icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(32)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(description)
                            .foregroundColor(Theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let bracketValue {
                            Text("(\(bracketValue))")
                                .foregroundColor(Theme.colors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if let secondaryDescription {
                        Text(secondaryDescription)
                            .foregroundColor(Theme.colors.textTertiary)
                            .lineLimit(1)
                    }

                }
            }
            accessoryView()
        }
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.textPrimary)
    }
}

extension SendCryptoTransactionDetailsRow where AccessoryView == EmptyView {
    init(
        title: String,
        description: String,
        secondaryDescription: String? = nil,
        bracketValue: String? = nil,
        icon: String? = nil
    ) {
        self.title = title
        self.description = description
        self.secondaryDescription = secondaryDescription
        self.bracketValue = bracketValue
        self.icon = icon
        self.accessoryView = { EmptyView() }
    }
}

#Preview {
    SendCryptoTransactionDetailsRow(title: "Test", description: "This is a test")
}
