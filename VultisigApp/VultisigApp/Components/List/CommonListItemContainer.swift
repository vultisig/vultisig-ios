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
        // The end rows carry the surface's corner radius themselves, so the
        // group reads as one rounded card without a mask spanning the whole
        // list. A container-height `clipShape` is a render-side cost that grows
        // with the row count and forces the list to be laid out as one unit.
        .clipShape(
            .rect(
                topLeadingRadius: isFirst ? CommonListContainer.cornerRadius : 0,
                bottomLeadingRadius: isLast ? CommonListContainer.cornerRadius : 0,
                bottomTrailingRadius: isLast ? CommonListContainer.cornerRadius : 0,
                topTrailingRadius: isFirst ? CommonListContainer.cornerRadius : 0
            )
        )
    }
}

/// Wrapping container for a group of `commonListItemContainer` rows: a single
/// rounded surface with a hairline border, matching the Figma list style.
struct CommonListContainer: ViewModifier {
    static let cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
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
