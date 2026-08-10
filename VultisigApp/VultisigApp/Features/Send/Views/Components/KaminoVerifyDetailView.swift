//
//  KaminoVerifyDetailView.swift
//  VultisigApp
//
//  What a Kamino Earn transaction does, read out of the bytes being signed.
//  Rendered on the initiator's Verify screen and on a co-signer's Join screen
//  from the same decode, so both devices are looking at the same claim.
//

import SwiftUI

struct KaminoVerifyDetailView: View {
    let state: KaminoVerifyPresentation.State

    var body: some View {
        switch state {
        case .notKamino:
            EmptyView()
        case .unreadable:
            unreadableBanner
        case .verified(let display):
            VStack(alignment: .leading, spacing: 12) {
                details(display)
            }
        case .amountUnverifiable(let display):
            VStack(alignment: .leading, spacing: 12) {
                // Not an alarm: everything that could be checked did check out.
                // What this says is which number came from the bytes, because
                // the one in the card above did not.
                InfoBannerView(
                    description: "kaminoVerifyAmountUnverifiable".localized,
                    type: .info,
                    leadingIcon: .circleInfo
                )
                details(display)
            }
        case .mismatch(let display, let disagreement):
            VStack(alignment: .leading, spacing: 12) {
                InfoBannerView(
                    description: disagreement.explanation,
                    type: .error,
                    leadingIcon: .triangleWarning
                )
                details(display)
            }
        }
    }

    /// The bytes invoke the kVaults program but do not read as a deposit or a
    /// withdraw. Said plainly rather than omitted: on this screen an empty space
    /// means "an ordinary transaction", which is the one thing this is not.
    private var unreadableBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoBannerView(
                description: "kaminoVerifyUnreadable".localized,
                type: .error,
                leadingIcon: .triangleWarning
            )
        }
    }

    /// What is left after the vault, curator and action moved into the summary's
    /// own row list: the amount as the BYTES state it, and the disclosures.
    ///
    /// The amount row stays because it is not the one above it. A withdraw is
    /// denominated in shares while the summary shows a token projection, and a
    /// full exit carries a sentinel rather than a quantity — so this is the
    /// figure that will actually be signed, and on a co-signer it is the only
    /// one that came from the bytes at all.
    @ViewBuilder
    private func details(_ display: KaminoVerifyPresentation.Display) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if display.amountAddsInformation {
                row(title: "kaminoVerifyAmount", value: display.amountWithUnit)
            }

            if display.strandsWrappedSolRent {
                // A SOL deposit wraps into an account this transaction opens and
                // never closes, so its rent leaves the spendable balance and only
                // comes back on a withdraw. Disclosed here as well as on the
                // form, because this is the screen where it is still refusable —
                // and because a co-signer never saw the form.
                InfoBannerView(
                    description: "kaminoDepositWrappedSolRent".localized,
                    type: .warning,
                    leadingIcon: .circleInfo
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
