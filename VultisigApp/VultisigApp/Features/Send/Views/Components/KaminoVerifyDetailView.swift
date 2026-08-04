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
                header(color: Theme.colors.textTertiary)
                details(display)
            }
        case .amountUnverifiable(let display):
            VStack(alignment: .leading, spacing: 12) {
                header(color: Theme.colors.textTertiary)
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
                header(color: Theme.colors.alertError)
                InfoBannerView(
                    description: disagreement.explanation,
                    type: .error,
                    leadingIcon: .triangleWarning
                )
                details(display)
            }
        }
    }

    private func header(color: Color) -> some View {
        Text("kaminoVerifyTitle".localized)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bytes invoke the kVaults program but do not read as a deposit or a
    /// withdraw. Said plainly rather than omitted: on this screen an empty space
    /// means "an ordinary transaction", which is the one thing this is not.
    private var unreadableBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(color: Theme.colors.alertError)
            InfoBannerView(
                description: "kaminoVerifyUnreadable".localized,
                type: .error,
                leadingIcon: .triangleWarning
            )
        }
    }

    @ViewBuilder
    private func details(_ display: KaminoVerifyPresentation.Display) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row(title: "kaminoVerifyAction", value: display.operationTitle)
            row(title: "kaminoVerifyVault", value: display.vaultName, bracketValue: display.vaultAddress)
            row(title: "kaminoVerifyAmount", value: display.amountWithUnit)
            row(
                title: "kaminoVerifyCurator",
                value: display.curator,
                trailing: display.riskTier.title,
                trailingColor: riskColor(for: display.riskTier)
            )

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgPrimary)
        .cornerRadius(Theme.radius.sm)
    }

    private func row(
        title: String,
        value: String,
        bracketValue: String? = nil,
        trailing: String? = nil,
        trailingColor: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let trailing {
                        Text(trailing)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(trailingColor ?? Theme.colors.textTertiary)
                    }
                }
                if let bracketValue {
                    Text(bracketValue)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Matches the Earn card: lending against tokenized private credit is a
    /// materially different risk and must not read as the same product.
    private func riskColor(for tier: KaminoRiskTier) -> Color {
        switch tier {
        case .conservative:
            Theme.colors.textTertiary
        case .privateCredit:
            Theme.colors.alertWarning
        }
    }
}
