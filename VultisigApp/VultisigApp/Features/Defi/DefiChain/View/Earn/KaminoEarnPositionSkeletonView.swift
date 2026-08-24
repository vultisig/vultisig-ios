//
//  KaminoEarnPositionSkeletonView.swift
//  VultisigApp
//

import SwiftUI

/// Placeholder for an Earn card whose figures have not arrived yet.
///
/// Shown only on a genuine first load — a warm store paints real rows from the
/// persisted snapshot before any network call, so this is the cold-start case
/// where the alternative is an empty segment that looks broken.
///
/// The shape mirrors `KaminoEarnView`'s card row for row: identity, deposited,
/// profit and loss, APY, then the action button. A placeholder that does not
/// match what replaces it reads as a layout jump rather than as loading.
struct KaminoEarnPositionSkeletonView: View {
    var body: some View {
        VStack(spacing: 16) {
            identityRow
            labelledValueRow(labelWidth: 70, valueWidth: 90)
            labelledValueRow(labelWidth: 84, valueWidth: 54)
            labelledValueRow(labelWidth: 96, valueWidth: 72)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            // The real row draws a `PrimaryButton`, which is a capsule. The
            // placeholder has to be the shape it stands in for, or the button
            // visibly changes shape the moment the data lands.
            Theme.radius.pill.shape
                .fill(placeholderFill)
                .frame(height: 44)
        }
        .padding(16)
        .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
        .overlay(Theme.radius.xl.shape.stroke(Theme.colors.border, lineWidth: 1))
        .redacted(reason: .placeholder)
        .shimmer()
        .accessibilityHidden(true)
    }

    private var identityRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Circle()
                    .fill(placeholderFill)
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(placeholderFill)
                    .frame(width: 36, height: 36)
                    .offset(x: 24)
            }
            .frame(width: 60, height: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Theme.radius.xs.shape
                    .fill(placeholderFill)
                    .frame(width: 128, height: 16)
                HStack(spacing: 3) {
                    Circle()
                        .fill(placeholderFill)
                        .frame(width: 16, height: 16)
                    Theme.radius.xs.shape
                        .fill(placeholderFill)
                        .frame(width: 52, height: 12)
                }
            }
            Spacer()
        }
    }

    private func labelledValueRow(labelWidth: CGFloat, valueWidth: CGFloat) -> some View {
        HStack {
            Theme.radius.xs.shape
                .fill(placeholderFill)
                .frame(width: labelWidth, height: 14)
            Spacer()
            Theme.radius.xs.shape
                .fill(placeholderFill)
                .frame(width: valueWidth, height: 14)
        }
    }

    private var placeholderFill: Color {
        Theme.colors.borderLight.opacity(0.3)
    }
}
