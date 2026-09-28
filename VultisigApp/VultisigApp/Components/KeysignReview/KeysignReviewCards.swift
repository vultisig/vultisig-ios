//
//  KeysignReviewCards.swift
//  VultisigApp
//

import SwiftUI

/// The raised card the review's parties and amounts sit on.
struct KeysignReviewCard<Content: View>: View {
    var minHeight: CGFloat = 0
    let content: () -> Content

    init(minHeight: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface2))
            .overlay(Theme.radius.lg.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
    }
}

enum KeysignReviewNotchGlyph {
    case chevronDown
    case chevronRight
    case plus
}

/// Only the small glyph badge: notched cards provide their own transparent
/// cavity, so no sheet-coloured disc should cover their shaped borders.
private struct KeysignReviewRelationBadge: View {
    static let size: CGFloat = 24
    let glyph: KeysignReviewNotchGlyph

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.bgSurface2)
                .frame(width: Self.size, height: Self.size)
            glyphView
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .chevronDown, .chevronRight:
            KeysignReviewChevron()
                .stroke(Theme.colors.textButtonDisabled, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(glyph == .chevronDown ? 90 : 0))
        case .plus:
            Icon(.plus, color: Theme.colors.textTertiary, size: 16)
        }
    }
}

/// One party to a transfer: an optional name over its address.
struct KeysignReviewParty: Equatable {
    let name: String?
    let address: String
}

/// Sender over recipient, joined by a downward notch.
struct KeysignReviewAddressCards: View {
    private static let spacing: CGFloat = 8

    let from: KeysignReviewParty
    let to: KeysignReviewParty

    var body: some View {
        VStack(spacing: Self.spacing) {
            card(for: from, isRecipient: false)
                .overlay(alignment: .bottom) {
                    // Anchor to the seam even when Dynamic Type makes the
                    // named sender taller than an unnamed recipient.
                    KeysignReviewRelationBadge(glyph: .chevronDown)
                        .offset(y: (KeysignReviewRelationBadge.size + Self.spacing) / 2)
                }
            card(for: to, isRecipient: true)
        }
    }

    private func card(for party: KeysignReviewParty, isRecipient: Bool) -> some View {
        let shape = NotchedRectangle(
            topLeadingRadius: Theme.radius.lg.points,
            topTrailingRadius: Theme.radius.lg.points,
            bottomLeadingRadius: Theme.radius.lg.points,
            bottomTrailingRadius: Theme.radius.lg.points,
            notchRadius: 20,
            notchCenterInset: Self.spacing / 2
        )
        return VStack(spacing: 4) {
            if let name = party.name {
                Text(name)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            Text(party.address)
                .foregroundStyle(party.name == nil ? Theme.colors.textSecondary : Theme.colors.textTertiary)
                .truncationMode(.middle)
        }
        .keysignReviewText(.bodyS)
        .lineLimit(1)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(shape.fill(Theme.colors.bgSurface2).rotationEffect(.degrees(isRecipient ? 180 : 0)))
        .overlay(shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1).rotationEffect(.degrees(isRecipient ? 180 : 0)))
    }
}

/// Two cards side by side, equally tall, joined by a notch.
struct KeysignReviewPairCards<Leading: View, Trailing: View>: View {
    private static var spacing: CGFloat { 8 }

    let glyph: KeysignReviewNotchGlyph
    let leading: () -> Leading
    let trailing: () -> Trailing

    init(
        glyph: KeysignReviewNotchGlyph,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.glyph = glyph
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            notchedCard(edge: .trailing, content: leading)
            notchedCard(edge: .leading, content: trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay { KeysignReviewRelationBadge(glyph: glyph) }
    }

    private func notchedCard<Content: View>(
        edge: HorizontalEdge,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(
                KeysignReviewHorizontalNotchedRectangle(
                    edge: edge,
                    notchCenterInset: Self.spacing / 2
                )
                .fill(Theme.colors.bgSurface2)
            )
            .overlay(
                KeysignReviewHorizontalNotchedRectangle(
                    edge: edge,
                    notchCenterInset: Self.spacing / 2
                )
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
            )
    }
}

/// The swap form's `NotchedRectangle`, turned onto a side edge for the review's
/// horizontal pair. The fill and border follow the cavity instead of relying
/// on a sheet-coloured circle to hide two ordinary rounded rectangles.
private struct KeysignReviewHorizontalNotchedRectangle: InsettableShape {
    let edge: HorizontalEdge
    var notchCenterInset: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let baseRect = CGRect(origin: .zero, size: CGSize(width: rect.height, height: rect.width))
        let base = NotchedRectangle(
            notchRadius: 20,
            notchCenterInset: notchCenterInset,
            insetAmount: insetAmount
        )
        let transform = switch edge {
        case .leading:
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.maxX, ty: rect.minY)
        case .trailing:
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.minX, ty: rect.maxY)
        }
        return base.path(in: baseRect).applying(transform)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// The amount being sent, with the coin's logo before it and its fiat value
/// under it.
struct KeysignReviewAmountHero: View {
    let logo: String
    let ticker: String
    let amount: String
    let fiat: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                AsyncImageView(logo: logo, size: CGSize(width: 24, height: 24), ticker: ticker, tokenChainLogo: nil)
                Text("\(amount) \(ticker)")
                    .keysignReviewText(.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let fiat, fiat.isNotEmpty {
                Text(fiat)
                    .keysignReviewText(.bodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A coin amount for a card: caption, logo, amount and fiat value.
struct KeysignReviewCoinAmount: View {
    let caption: String?
    let logo: String
    /// Stands in for the logo when it cannot load.
    let ticker: String
    let amountText: String
    let fiat: String?

    var body: some View {
        VStack(spacing: 8) {
            if let caption {
                Text(caption)
                    .keysignReviewText(.bodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            AsyncImageView(logo: logo, size: CGSize(width: 36, height: 36), ticker: ticker, tokenChainLogo: nil)
            VStack(spacing: 0) {
                Text(amountText)
                    .keysignReviewText(.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                if let fiat, fiat.isNotEmpty {
                    Text(fiat)
                        .keysignReviewText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
