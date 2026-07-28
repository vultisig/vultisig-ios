//
//  UnverifiedTokenBottomSheet.swift
//  VultisigApp
//

import SwiftUI

/// Risk confirm shown when a pending token selection adds one or more
/// `.unverified` tokens. Deliberately does NOT list them: the sheet exists to
/// make the user pause on the fact that their selection includes unverified
/// entries, not to be a wall of tickers and addresses nobody reads. Mirrors
/// `SecurityScannerBottomSheet`: the safe action is the primary button,
/// "continue anyway" is the quiet secondary.
///
/// Trade-off to be aware of when changing this: the ⚠ badge on the grid cell
/// marks *which* tokens are unverified, but nothing in this flow surfaces a
/// token's contract address, so a user facing two same-ticker lookalikes cannot
/// tell them apart here. Restoring that belongs on the cell (a detail
/// disclosure), not by re-listing tokens in this confirm.
struct UnverifiedTokenBottomSheet: View, BottomSheetProperties {
    let onCancel: () -> Void
    let onContinue: () -> Void

    var bgColor: Color? { Theme.colors.bgPrimary }

    var body: some View {
        VStack(spacing: 24) {
            Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 24)

            VStack(spacing: 12) {
                Text("addUnverifiedTokenTitle".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title2)

                Text("addUnverifiedTokenMessage".localized)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                PrimaryButton(title: "cancel".localized, action: onCancel)

                Button("continueAnyway".localized, action: onContinue)
                    .frame(height: 42, alignment: .center)
                    .foregroundStyle(Theme.colors.textButtonDisabled)
                    .font(Theme.fonts.caption10)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    UnverifiedTokenBottomSheet(onCancel: {}, onContinue: {})
        .background(Theme.colors.bgPrimary)
}
