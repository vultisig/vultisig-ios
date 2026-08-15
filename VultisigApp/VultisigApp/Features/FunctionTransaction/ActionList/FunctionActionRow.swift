//
//  FunctionActionRow.swift
//  VultisigApp
//
//  Renders one `FunctionActionDescriptor`. Deliberately knows nothing about
//  where the descriptor came from or where it goes — it takes a value and a
//  closure — so the DeFi tab can render the same rows without inheriting the
//  action list's navigation.
//

import SwiftUI

struct FunctionActionRow: View {
    let descriptor: FunctionActionDescriptor
    let onSelect: () -> Void

    /// An unavailable action explains itself in place of its subtitle: the
    /// reason is the more useful of the two lines, and stacking both makes the
    /// row read as a warning.
    private var detail: String? {
        descriptor.unavailableReason ?? descriptor.subtitle
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Icon(descriptor.icon, color: Theme.colors.textPrimary, size: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textPrimary)

                    if let detail {
                        Text(detail)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                Icon(.chevronRight, color: Theme.colors.textTertiary, size: 16)
                    .showIf(descriptor.isAvailable)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!descriptor.isAvailable)
        .opacity(descriptor.isAvailable ? 1 : 0.5)
    }
}

#Preview {
    VStack(spacing: 0) {
        FunctionActionRow(
            descriptor: FunctionActionDescriptor(
                id: "leave",
                title: "Leave",
                subtitle: "Ask a node to leave and release your bond",
                icon: .arrowToCornerTopRight,
                destination: .transaction(.leave(coin: Coin.example.toCoinMeta(), node: nil))
            ),
            onSelect: {}
        )
        FunctionActionRow(
            descriptor: FunctionActionDescriptor(
                id: "custom",
                title: "Custom",
                subtitle: "Send a transaction with a custom memo",
                icon: .filePen,
                availability: .unavailable(reason: "Not available on this chain"),
                destination: .transaction(.customMemo(coin: Coin.example.toCoinMeta()))
            ),
            onSelect: {}
        )
    }
    .commonListContainer()
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
