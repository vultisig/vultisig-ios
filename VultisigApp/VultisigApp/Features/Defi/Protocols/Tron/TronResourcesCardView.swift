//
//  TronResourcesCardView.swift
//  VultisigApp
//
//  Reusable Bandwidth & Energy resources card for TRON chains.
//

import SwiftUI

struct TronResourcesCardView: View {
    let availableBandwidth: Int64
    let totalBandwidth: Int64
    let availableEnergy: Int64
    let totalEnergy: Int64
    let isLoading: Bool

    @State private var showInfoSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // Bandwidth Section (Green)
            resourceSection(
                title: NSLocalizedString("tronBandwidth", comment: "Bandwidth"),
                icon: "gauge.with.needle",
                available: availableBandwidth,
                total: max(totalBandwidth, 1),
                accentColor: Theme.colors.alertSuccess,
                unit: "KB"
            )
            .padding(.leading, 16)
            .padding(.trailing, 12)

            // Vertical divider
            Rectangle()
                .fill(Theme.colors.textSecondary.opacity(0.3))
                .frame(width: 1)

            // Energy Section (Yellow/Orange)
            resourceSection(
                title: NSLocalizedString("tronEnergy", comment: "Energy"),
                icon: "bolt.fill",
                available: availableEnergy,
                total: max(totalEnergy, 1),
                accentColor: Theme.colors.alertWarning,
                unit: ""
            )
            .padding(.leading, 12)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(
            TronConstants.Design.cornerRadius.shape
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            TronConstants.Design.cornerRadius.shape
                .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .crossPlatformSheet(isPresented: $showInfoSheet) {
            TronResourcesInfoSheet(onDismiss: { showInfoSheet = false })
        }
    }

    // MARK: - Resource Section

    private func resourceSection(
        title: String,
        icon: String,
        available: Int64,
        total: Int64,
        accentColor: Color,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(accentColor)

            HStack(spacing: 8) {
                ZStack {
                    Theme.radius.sm.shape
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        Theme.radius.xs.shape
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 60, height: 14)
                            .shimmer()
                    } else {
                        Text(TronViewLogic.formatResourceValue(available: available, total: total, unit: unit))
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }

                    GeometryReader { geometry in
                        // The three 2s below are off the scale on purpose: they
                        // are the end caps of a 3pt-tall progress bar, sized
                        // against its own thickness rather than against a
                        // surface. At 3pt the radius is already past SwiftUI's
                        // half-the-smaller-dimension clamp, so the bar renders
                        // fully round whatever number is written here.
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2) // swiftlint:disable:this no_raw_corner_radius
                                .fill(Theme.colors.bgPrimary)
                                .frame(height: 3)

                            if isLoading {
                                RoundedRectangle(cornerRadius: 2) // swiftlint:disable:this no_raw_corner_radius
                                    .fill(accentColor.opacity(0.3))
                                    .frame(width: geometry.size.width * 0.5, height: 3)
                                    .shimmer()
                            } else {
                                RoundedRectangle(cornerRadius: 2) // swiftlint:disable:this no_raw_corner_radius
                                    .fill(accentColor)
                                    .frame(width: geometry.size.width * progressValue(available: available, total: total), height: 3)
                            }
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressValue(available: Int64, total: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        return min(CGFloat(available) / CGFloat(total), 1.0)
    }
}
