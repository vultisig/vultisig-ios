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

/// The disc over the seam between two cards, saying how they relate.
struct KeysignReviewNotch: View {
    let glyph: KeysignReviewNotchGlyph

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.bgSurface1)
                .overlay(Circle().strokeBorder(Theme.colors.borderLight, lineWidth: 1))
                .frame(width: 40, height: 40)
            Circle()
                .fill(Theme.colors.bgSurface2)
                .frame(width: 24, height: 24)
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
    let from: KeysignReviewParty
    let to: KeysignReviewParty

    var body: some View {
        VStack(spacing: 8) {
            card(for: from)
            card(for: to)
        }
        .overlay { KeysignReviewNotch(glyph: .chevronDown) }
    }

    private func card(for party: KeysignReviewParty) -> some View {
        KeysignReviewCard(minHeight: 82) {
            VStack(spacing: 4) {
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
        }
    }
}

/// Two cards side by side, equally tall, joined by a notch.
struct KeysignReviewPairCards<Leading: View, Trailing: View>: View {
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
        HStack(spacing: 8) {
            KeysignReviewCard { leading().frame(maxHeight: .infinity) }
            KeysignReviewCard { trailing().frame(maxHeight: .infinity) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay { KeysignReviewNotch(glyph: glyph) }
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
