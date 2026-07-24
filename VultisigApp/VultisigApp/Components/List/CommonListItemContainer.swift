//
//  CommonListItemContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct CommonListItemContainer: ViewModifier {
    let index: Int
    let itemsCount: Int

    var isFirst: Bool {
        index == 0
    }

    var isLast: Bool {
        index == itemsCount - 1
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Separator(color: Theme.colors.borderLight, opacity: 1)
                .showIf(!isLast)
        }
        .clipShape(
            .rect(
                topLeadingRadius: isFirst ? 12 : 0,
                bottomLeadingRadius: isLast ? 12 : 0,
                bottomTrailingRadius: isLast ? 12 : 0,
                topTrailingRadius: isFirst ? 12 : 0
            )
        )
        .plainListItem()
    }
}

/// Wrapping container for a group of `commonListItemContainer` rows: a single
/// rounded surface with a hairline border, matching the Figma list style.
struct CommonListContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func commonListItemContainer(index: Int, itemsCount: Int) -> some View {
        modifier(CommonListItemContainer(index: index, itemsCount: itemsCount))
    }

    func commonListContainer() -> some View {
        modifier(CommonListContainer())
    }
}
