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
            row(label: "rippleFieldType".localized, value: transaction.transactionType)
            ForEach(Array(transaction.fields.enumerated()), id: \.offset) { _, field in
                fieldRows(field)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
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
            HStack(alignment: .top, spacing: 8) {
                Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 16)
                Text("rippleUndecodedNotice".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(signRipple.rawJson)
                .font(Theme.fonts.caption12)
                .monospaced()
                .foregroundStyle(Theme.colors.turquoise)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.colors.bgPrimary)
                .cornerRadius(8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
    }

    // MARK: - Building blocks

    private var header: some View {
        Text("rippleTransactionSummary".localized)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
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
