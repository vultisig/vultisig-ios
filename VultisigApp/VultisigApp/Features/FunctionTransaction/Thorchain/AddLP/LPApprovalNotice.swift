//
//  LPApprovalNotice.swift
//  VultisigApp
//

import SwiftUI

/// The notice an ERC-20 liquidity deposit shows when an approve is signed
/// ahead of it. Shown on Verify, where the approval has been read; the form
/// cannot know yet whether the current allowance already covers the deposit.
struct LPApprovalNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("erc20ApprovalRequired".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("approvalRequiredMessageLP".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("approvalTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
                Text("addLiquidityTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
            }
            .padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.colors.bgNeutral)
        .cornerRadius(Theme.radius.sm)
    }
}
