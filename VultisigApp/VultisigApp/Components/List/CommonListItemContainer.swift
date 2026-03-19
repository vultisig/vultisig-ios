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
            GradientListSeparator()
                .showIf(isFirst)
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

extension View {
    func commonListItemContainer(index: Int, itemsCount: Int) -> some View {
        modifier(CommonListItemContainer(index: index, itemsCount: itemsCount))
    }
}
