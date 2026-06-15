//
//  LockedFeatureSheet.swift
//  VultisigApp
//

import SwiftUI

/// Generic tier-locked feature sheet, shown to vaults below the tier a feature
/// requires. Presents the requirement and a path to unlock, sourcing the tier,
/// threshold, and balance comparison from the tier system. The feature-specific
/// icon and copy come from the `LockedFeature` descriptor.
struct LockedFeatureSheet: View {
    @ObservedObject var vault: Vault
    @Binding var isPresented: Bool
    var onUnlock: () -> Void

    @StateObject private var viewModel: LockedFeatureSheetViewModel
    @State private var width: CGFloat = 0

    init(
        feature: LockedFeature,
        vault: Vault,
        isPresented: Binding<Bool>,
        onUnlock: @escaping () -> Void
    ) {
        self.vault = vault
        self._isPresented = isPresented
        self.onUnlock = onUnlock
        self._viewModel = StateObject(
            wrappedValue: LockedFeatureSheetViewModel(feature: feature)
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            requiresCard
            buttons
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        #if os(macOS)
        .applySheetSize(400, 540)
        #endif
        .background(ModalBackgroundView(width: width))
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDetents([.height(540)])
        .presentationDragIndicator(.visible)
        .readSize { width = $0.width }
        .task { await viewModel.loadBalance(for: vault) }
    }

    private var header: some View {
        VStack(spacing: 32) {
            iconBadge
            VStack(spacing: 16) {
                Text(viewModel.feature.titleKey.localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(viewModel.feature.subtitleKey.localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var iconBadge: some View {
        Icon(named: viewModel.feature.icon, color: Theme.colors.primaryAccent4, size: 20)
            .frame(width: 40, height: 40)
            .background(Theme.colors.primaryAccent4.opacity(0.12))
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Theme.colors.primaryAccent4.opacity(0.5), lineWidth: 1)
            )
    }

    private var requiresCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("customRPCsLockedRequires".localized)
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                VultDiscountTierIcon(tier: viewModel.requiredTier, size: .small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: "customRPCsLockedTierRequirement".localized,
                            viewModel.requiredTier.name.localized
                        )
                    )
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    Text(
                        String(
                            format: "customRPCsLockedTierSubtitle".localized,
                            viewModel.thresholdText
                        )
                    )
                    .font(Theme.fonts.priceFootnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer(minLength: 0)
            }

            balanceRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private var balanceRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Icon(named: "wallet-4", color: Theme.colors.textTertiary, size: 16)
                Text("customRPCsLockedYourBalance".localized)
                    .font(Theme.fonts.priceFootnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer(minLength: 0)
            Text(viewModel.balanceText)
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(
                    viewModel.isBelowThreshold
                        ? Theme.colors.alertWarning
                        : Theme.colors.textPrimary
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.colors.bgSurface12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "customRPCsLockedGetVult".localized) {
                onUnlock()
            }
            PrimaryButton(title: "customRPCsLockedBack".localized, type: .secondary) {
                isPresented = false
            }
        }
    }
}

#Preview {
    LockedFeatureSheet(
        feature: .customRPC,
        vault: .example,
        isPresented: .constant(true)
    ) {}
}
