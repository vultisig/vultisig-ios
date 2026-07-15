//
//  BeforeYouReshareBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI

/// Pre-flight warning shown before starting a reshare: old backups become
/// invalid and enough current co-signers to meet the threshold must be online.
struct BeforeYouReshareBottomSheet: View, BottomSheetProperties {
    let onContinue: () -> Void

    /// Natural height of the (unscrolled) warning content. Used to size the
    /// scroll region so the sheet still hugs its content on roomy screens while
    /// scrolling — instead of clipping the pinned button — under large
    /// Accessibility Dynamic Type or on short screens.
    @State private var contentHeight: CGFloat = .zero

    var bgColor: Color? { Theme.colors.bgPrimary }

    var body: some View {
        VStack(spacing: 10) {
            scrollableContent
            PrimaryButton(title: "iUnderstand", action: onContinue)
        }
        .padding(.top, 10)
        .padding(.bottom, 16)
        .onPreferenceChange(ReshareSheetContentHeightKey.self) { contentHeight = $0 }
    }

    @ViewBuilder
    var scrollableContent: some View {
        if contentHeight > 0 {
            ScrollView {
                measuredContent
            }
            .frame(maxHeight: contentHeight)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            // First layout pass: render unscrolled so the sheet can measure the
            // natural content height and size its detent before we wrap the
            // content in a (greedy) ScrollView.
            measuredContent
        }
    }

    var measuredContent: some View {
        VStack(spacing: 10) {
            header
            warningCards
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReshareSheetContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
    }

    var header: some View {
        VStack(spacing: 12) {
            Text("beforeYouReshare".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("beforeYouReshareSubtitle".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: 257)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    var warningCards: some View {
        VStack(spacing: 10) {
            ReshareWarningCard(
                icon: "file-tree",
                title: "newBackupsCreatedTitle".localized,
                subtitle: "newBackupsCreatedDescription".localized
            )

            ReshareWarningCard(
                icon: "traffic-cone",
                title: "oldBackupsOnlyWorkTogetherTitle".localized,
                subtitle: "oldBackupsOnlyWorkTogetherDescription".localized
            )

            ReshareWarningCard(
                icon: "circles-5",
                title: "requiredCosignersOnlineTitle".localized,
                subtitle: "requiredCosignersOnlineDescription".localized
            )
        }
    }
}

private struct ReshareWarningCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(
                named: icon,
                color: Theme.colors.alertWarning,
                size: 24
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(subtitle)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct ReshareSheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    BeforeYouReshareBottomSheet(onContinue: {})
        .background(Theme.colors.bgPrimary)
}
