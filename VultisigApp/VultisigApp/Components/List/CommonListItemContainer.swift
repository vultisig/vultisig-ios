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

    /// Only the end rows have a non-zero radius, so only they need a mask. A
    /// middle row's clip is a plain rectangle the size of the row — visually a
    /// no-op that still installs a mask and can cost an offscreen pass, once
    /// per row, on every frame the list composites.
    private var needsCornerClip: Bool {
        isFirst || isLast
    }

    func body(content: Content) -> some View {
        // The end rows carry the surface's corner radius themselves, so the
        // group reads as one rounded card without a mask spanning the whole
        // list. A container-height `clipShape` is a render-side cost that grows
        // with the row count and forces the list to be laid out as one unit.
        if needsCornerClip {
            // A single-row list is both first and last, so it keeps all four
            // corners rounded.
            row(content)
                .clipShape(
                    .rect(
                        topLeadingRadius: isFirst ? CommonListContainer.cornerRadius.points : 0,
                        bottomLeadingRadius: isLast ? CommonListContainer.cornerRadius.points : 0,
                        bottomTrailingRadius: isLast ? CommonListContainer.cornerRadius.points : 0,
                        topTrailingRadius: isFirst ? CommonListContainer.cornerRadius.points : 0,
                        // Rounding each corner separately means this cannot use
                        // the token's `shape`, so the style has to be carried
                        // across by hand — otherwise these row masks would keep
                        // the SDK's default while the container follows the
                        // token, and the two would diverge the moment the
                        // token's style changes.
                        style: CommonListContainer.cornerRadius.style
                    )
                )
        } else {
            row(content)
        }
    }

    private func row(_ content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Separator(color: Theme.colors.borderLight, opacity: 1)
                .showIf(!isLast)
        }
    }
}

/// Wrapping container for a group of `commonListItemContainer` rows: a single
/// rounded surface with a hairline border, matching the Figma list style.
struct CommonListContainer: ViewModifier {
    static let cornerRadius = Theme.radius.xl

    func body(content: Content) -> some View {
        content
            .background(
                Self.cornerRadius.shape
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                Self.cornerRadius.shape
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
