//
//  CommonListItemContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

/// How a group of list rows is drawn.
enum CommonListStyle {
    /// A hairline-bordered card whose separators sit between the rows.
    case outlined
    /// A borderless card whose separators are drawn inside each row's own
    /// height, so a row keeps the design's height whether it has one or not.
    case flush
    /// A flush card with a hairline drawn over its edge.
    case flushOutlined
}

struct CommonListItemContainer: ViewModifier {
    let index: Int
    let itemsCount: Int
    let style: CommonListStyle

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
    ///
    /// A flush card clips once at the container, so its rows never need one.
    private var needsCornerClip: Bool {
        style == .outlined && (isFirst || isLast)
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

    @ViewBuilder
    private func row(_ content: Content) -> some View {
        switch style {
        case .outlined:
            VStack(spacing: 0) {
                content
                separator
            }
        case .flush, .flushOutlined:
            content
                .overlay(alignment: .bottom) { separator }
        }
    }

    private var separator: some View {
        Separator(color: Theme.colors.borderLight, opacity: 1)
            .showIf(!isLast)
    }
}

/// Wrapping container for a group of `commonListItemContainer` rows: a single
/// rounded surface, outlined by a hairline or flush with the screen.
struct CommonListContainer: ViewModifier {
    static let cornerRadius = Theme.radius.xl
    /// The flush card's rows start one point below its top edge.
    static let flushTopInset: CGFloat = 1
    /// A screen's top inset that puts a flush card's rows 12 below the toolbar.
    static let flushScreenTopInset: CGFloat = 12 - flushTopInset

    let style: CommonListStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .outlined:
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
        case .flush:
            content
                .background(Theme.colors.bgSurface1)
                .padding(.top, Self.flushTopInset)
                .clipShape(Self.cornerRadius.shape)
        case .flushOutlined:
            content
                .background(Theme.colors.bgSurface1)
                .clipShape(Self.cornerRadius.shape)
                .overlay(
                    Self.cornerRadius.shape
                        .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }
}

extension View {
    func commonListItemContainer(index: Int, itemsCount: Int, style: CommonListStyle = .outlined) -> some View {
        modifier(CommonListItemContainer(index: index, itemsCount: itemsCount, style: style))
    }

    func commonListContainer(style: CommonListStyle = .outlined) -> some View {
        modifier(CommonListContainer(style: style))
    }
}
