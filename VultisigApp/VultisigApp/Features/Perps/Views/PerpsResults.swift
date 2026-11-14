//
//  PerpsResults.swift
//  VultisigApp
//
//  Perps states: one outcome, one next action. Used for a pending
//  deposit, a first trade that opened, and a closed position. A dry run never
//  reaches these on its own, so debug builds show them behind the debug launch
//  flag `-perpsDemoState addingFunds,tradeOpened,positionClosed`: adding
//  funds on the hub, trade opened after a review is closed, position closed
//  when Close is tapped. Numbers come from live market and position data.
//

import SwiftUI

struct PerpsResultSheet: View {
    enum Mark { case success, pending, failure, waiting }

    var mark: Mark?
    /// Small line above the title ("BTC position closed").
    var caption: String?
    let title: String
    var titleColor: Color = Theme.colors.textPrimary
    var titleIsAmount = false
    let message: String
    var statusRows: [PerpsReviewRow] = []
    /// One quiet line under the status rows.
    var note: String?
    var details: [PerpsReviewRow] = []
    let actionTitle: String
    var actionType: ButtonType = .primary
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    /// A line under the buttons with a text link: "Not there in an hour? Get help".
    var helpLine: (prompt: String, link: String, action: () -> Void)?
    let action: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: PerpsLayout.section) {
            VStack(spacing: 10) {
                markView
                if let caption {
                    Text(caption)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                Text(title)
                    .font(titleIsAmount ? Theme.fonts.priceLargeTitle : Theme.fonts.title2)
                    .monospacedDigit()
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            if !statusRows.isEmpty {
                VStack(spacing: 10) {
                    PerpsCard {
                        ForEach(Array(statusRows.enumerated()), id: \.offset) { index, row in
                            PerpsRow(title: row.label, value: row.value, valueColor: row.color, showsDivider: index > 0)
                        }
                    }
                    if let note { PerpsFootnote(text: note) }
                }
            }
            if !details.isEmpty {
                PerpsCard {
                    Button { showsDetails.toggle() } label: {
                        PerpsRow(title: "perpsDetails".localized, value: nil) {
                            // down when collapsed, up when open, like the review's Details.
                            Icon(.chevronDown, color: Theme.colors.textTertiary, size: 16)
                                .rotationEffect(.degrees(showsDetails ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("perpsResultDetails")
                    if showsDetails {
                        ForEach(Array(details.enumerated()), id: \.offset) { _, row in
                            PerpsRow(title: row.label, value: row.value, valueColor: row.color, showsDivider: true)
                        }
                    }
                }
            }
            VStack(spacing: 10) {
                PrimaryButton(title: actionTitle, type: actionType, action: action)
                    .accessibilityIdentifier("perpsResultAction")
                if let secondaryActionTitle, let secondaryAction {
                    PrimaryButton(title: secondaryActionTitle, type: .secondary, action: secondaryAction)
                        .accessibilityIdentifier("perpsResultSecondaryAction")
                }
                if let helpLine {
                    Button(action: helpLine.action) {
                        (Text(helpLine.prompt + " ").foregroundStyle(Theme.colors.textSecondary)
                            + Text(helpLine.link).foregroundStyle(Theme.colors.primaryAccent4))
                            .font(Theme.fonts.bodySRegular)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("perpsResultHelp")
                }
            }
        }
        .perpsSheetChrome()
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .success:
            Circle()
                .fill(Theme.colors.alertSuccess.opacity(0.14))
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .fill(Theme.colors.alertSuccess)
                        .frame(width: 40, height: 40)
                        .overlay(Icon(.check, color: Theme.colors.bgPrimary, size: 20))
                )
        case .failure:
            Circle()
                .fill(Theme.colors.alertError.opacity(0.14))
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .fill(Theme.colors.alertError)
                        .frame(width: 40, height: 40)
                        .overlay(Icon(.xmark, color: Theme.colors.textPrimary, size: 18))
                )
        case .waiting:
            Circle()
                .fill(Theme.colors.primaryAccent3.opacity(0.16))
                .frame(width: 64, height: 64)
                .overlay(
                    Icon(.clock, color: Theme.colors.primaryAccent4, size: 26)
                )
        case .pending:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.colors.primaryAccent4)
                .frame(width: 64, height: 64)
        case nil:
            EmptyView()
        }
    }
}
