//
//  SignRippleDisplayView.swift
//  VultisigApp
//
//  Renders the decoded XRPL transaction carried by a `signRipple` keysign
//  payload on the verify / join screens, so a co-signer reviews readable terms
//  — type, destination, amounts, issuer — instead of an empty "0 XRP" send
//  card. Falls back to the raw JSON with a caution notice when the transaction
//  can't be decoded: a signing screen must never go blank. Mirrors the Windows
//  `SignRippleDisplay`.
//
//  Caveats that redefine those rows lead the card: a `tfPartialPayment` payment
//  whose amount is only a ceiling, and a site-supplied routing path. Both are
//  signed verbatim, so a screen showing the rows without them would state
//  better terms than the ones being approved.
//

import SwiftUI

struct SignRippleDisplayView: View {
    let signRipple: SignRipple

    private var decoded: RippleDAppTransaction? {
        RippleDAppTransaction.parse(rawJson: signRipple.rawJson)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let decoded {
                decodedCard(decoded)
            } else {
                fallbackCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Decoded

    private func decodedCard(_ transaction: RippleDAppTransaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(transaction.warnings, id: \.labelKey) { warning in
                warningRow(warning.labelKey.localized)
            }
            row(label: "rippleFieldType".localized, value: transaction.transactionType)
            ForEach(Array(transaction.fields.enumerated()), id: \.offset) { _, field in
                fieldRows(field)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface2))
    }

    @ViewBuilder
    private func fieldRows(_ field: RippleDAppTransaction.Field) -> some View {
        switch field.value {
        case let .text(text):
            row(label: field.labelKey.localized, value: text, mono: field.labelKey == "rippleFieldDestination")
        case let .amount(amount):
            switch amount {
            case let .native(xrp):
                row(label: field.labelKey.localized, value: "\(xrp) XRP", valueFont: Theme.fonts.priceBodyS)
            case let .issued(value, currency, issuer):
                row(label: field.labelKey.localized, value: "\(value) \(currency)", valueFont: Theme.fonts.priceBodyS)
                row(label: "rippleFieldIssuer".localized, value: issuer, mono: true)
            }
        }
    }

    // MARK: - Fallback

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            warningRow("rippleUndecodedNotice".localized)
            Text(signRipple.rawJson)
                .font(Theme.fonts.caption12)
                .monospaced()
                .foregroundStyle(Theme.colors.turquoise)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.colors.bgPrimary)
                .cornerRadius(Theme.radius.sm)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface2))
    }

    // MARK: - Building blocks

    private var header: some View {
        Text("rippleTransactionSummary".localized)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    /// A full-width caution line. Unlike `row`, the text is not squeezed against
    /// a trailing edge — a warning is prose, and it has to stay readable when it
    /// wraps to two or three lines.
    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 16)
            Text(text)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertWarning)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(
        label: String,
        value: String,
        valueFont: Font = Theme.fonts.caption12,
        mono: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(valueFont)
                .monospaced(mono)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
