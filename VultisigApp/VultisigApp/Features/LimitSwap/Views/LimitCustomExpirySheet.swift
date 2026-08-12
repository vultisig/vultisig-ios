//
//  LimitCustomExpirySheet.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Custom expiry sheet
//
// Edits a DURATION, because a duration is what the memo stores. A date/time
// picker was the original request, but the TTL is a block count started when the
// order joins the queue, so an absolute time chosen here would silently drift by
// the whole deposit-confirmation delay. Days/hours/minutes is the honest control,
// and the copy states what it is relative to.

struct LimitCustomExpirySheet: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var isPresented: Bool

    @State private var days = 0
    @State private var hours = 0
    @State private var minutes = 0

    private var selectedBlocks: Int {
        THORChainConstants.blocks(forMinutes: days * 1440 + hours * 60 + minutes)
    }

    private var isAtCeiling: Bool { selectedBlocks >= vm.maxExpiryBlocks }
    private var isBelowFloor: Bool { selectedBlocks < vm.minExpiryBlocks }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("limitSwap.expiry.customTitle".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Text(String(
                    format: "limitSwap.expiry.maxHint".localized,
                    formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                ))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            }

            HStack(spacing: 10) {
                stepper(titleKey: "limitSwap.expiry.daysUnit", value: $days, range: 0...maxDays)
                stepper(titleKey: "limitSwap.expiry.hoursUnit", value: $hours, range: 0...23)
                stepper(titleKey: "limitSwap.expiry.minutesUnit", value: $minutes, range: 0...59, step: 5)
            }

            noticeRow

            Spacer(minLength: 0)

            PrimaryButton(title: "limitSwap.expiry.set".localized) {
                vm.selectExpiryBlocks(selectedBlocks)
                isPresented = false
            }
            .disabled(isBelowFloor)
        }
        .padding(16)
        // Presented content, not a screen — see `LimitCustomOffsetSheet` for why
        // this is `.medium` rather than a pinned height.
        .sheetStyle(detents: [.medium])
        .onLoad {
            // Seed from the live draft so reopening the sheet shows what is set.
            let total = THORChainConstants.minutes(forBlocks: vm.draft.expiryBlocks)
            days = total / 1440
            hours = (total % 1440) / 60
            minutes = total % 60
        }
    }

    private var maxDays: Int {
        THORChainConstants.minutes(forBlocks: vm.maxExpiryBlocks) / 1440
    }

    /// Says which bound was hit and why, instead of letting the value be silently
    /// corrected. THORChain clamps an over-long TTL on-chain without an error, so
    /// an app that mirrored that behaviour would leave the user believing they had
    /// set a week.
    @ViewBuilder
    private var noticeRow: some View {
        if isAtCeiling {
            LimitInlineNotice(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.colors.alertWarning,
                message: String(
                    format: "limitSwap.expiry.ceilingNotice".localized,
                    formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                )
            )
        } else if isBelowFloor {
            LimitInlineNotice(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.colors.alertWarning,
                message: String(
                    format: "limitSwap.expiry.floorNotice".localized,
                    formatLimitExpiry(blocks: vm.minExpiryBlocks)
                )
            )
        } else {
            LimitInlineNotice(
                systemImage: "clock",
                tint: Theme.colors.alertSuccess,
                message: String(
                    format: "limitSwap.expiry.restsFor".localized,
                    formatLimitExpiry(blocks: selectedBlocks)
                )
            )
        }
    }

    private func stepper(titleKey: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(spacing: 6) {
            Text(titleKey.localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                stepButton(systemImage: "minus", enabled: value.wrappedValue > range.lowerBound) {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                Text("\(value.wrappedValue)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(minWidth: 26)
                stepButton(systemImage: "plus", enabled: value.wrappedValue < range.upperBound) {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(
            Theme.radius.md.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(Theme.radius.md.shape)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                .frame(width: 24, height: 24)
                .background(Theme.colors.bgSurface2)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
