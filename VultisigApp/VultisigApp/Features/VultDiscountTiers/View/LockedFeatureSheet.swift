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
    enum Appearance {
        case standard
        /// The settings sheet: page background, wider card, taller detent.
        case settings
    }

    @ObservedObject var vault: Vault
    @Binding var isPresented: Bool
    var onUnlock: () -> Void
    private let appearance: Appearance

    @StateObject private var viewModel: LockedFeatureSheetViewModel

    private let footerHeight: CGFloat = 48
    private let footerRadius: CornerRadius = Theme.radius.xl
    /// Deliberately off the scale — mirrors `VultDiscountTierView`'s card, whose
    /// 20pt bottom is a Figma value the footer bar is drawn to sit under.
    private let cardCornerRadius: CGFloat = 20 // swiftlint:disable:this no_raw_corner_radius
    private let settingsCardTopRadius: CGFloat = 24 // swiftlint:disable:this no_raw_corner_radius
    private let settingsFooterRadius: CGFloat = 24 // swiftlint:disable:this no_raw_corner_radius
    private let settingsBalanceRadius: CGFloat = 14 // swiftlint:disable:this no_raw_corner_radius
    private let settingsFooterHeight: CGFloat = 74
    private let settingsFooterOverlap: CGFloat = 22
    private let settingsDetent: CGFloat = 565
    private let settingsHeaderInset: CGFloat = 28
    private let settingsBadgeDiameter: CGFloat = 40

    init(
        feature: LockedFeature,
        vault: Vault,
        isPresented: Binding<Bool>,
        appearance: Appearance = .standard,
        onUnlock: @escaping () -> Void
    ) {
        self.appearance = appearance
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
        }
        .padding(.top, 40)
        .padding(.horizontal, isSettings ? 16 : 24)
        .padding(.bottom, 24)
        #if os(macOS)
        .applySheetSize(400, isSettings ? settingsDetent : 460)
        #endif
        .presentationBackground(isSettings ? Theme.colors.bgPrimary : Theme.colors.bgSurface1)
        .presentationDetents([.height(isSettings ? settingsDetent : 460)])
        .presentationDragIndicator(.visible)
        .onAppear { viewModel.loadBalance(for: vault) }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented = false
                }
            }
        }
    }

    private var isSettings: Bool {
        appearance == .settings
    }

    @ViewBuilder
    private var header: some View {
        if isSettings {
            VStack(spacing: 32) {
                settingsBadge
                VStack(spacing: 16) {
                    Text(viewModel.feature.titleKey.localized)
                        .settingsText(.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(viewModel.feature.subtitleKey.localized)
                        .settingsText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, settingsHeaderInset)
            }
        } else {
            VStack(spacing: 32) {
                VaultSetupStepIcon(state: .active, icon: viewModel.feature.icon)
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
    }

    /// `cardContent` sits on top (`zIndex`) with the `Get $VULT` gradient footer
    /// tucked behind its rounded bottom and peeking below — mirroring the layered
    /// footer in `VultDiscountTierView`. Both are real layout elements (a VStack,
    /// not an offset overlay) so the footer's peek stays reliably tappable.
    private var requiresCard: some View {
        VStack(spacing: 0) {
            if isSettings {
                settingsCardContent
                    .zIndex(1)
                settingsFooter
                    .padding(.top, -settingsFooterOverlap)
            } else {
                cardContent
                    .zIndex(1)
                getVultFooter
                    .padding(.top, -cardCornerRadius)
            }
        }
    }

    private var settingsBadge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "03132C"))
            Rectangle()
                .fill(Color(hex: "0C4EFF"))
                .frame(width: 16, height: 8)
                .blur(radius: 9.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
            Circle()
                .inset(by: 0.75)
                .stroke(.white.opacity(0.15), lineWidth: 1.5)
            Icon(viewModel.feature.icon, color: Theme.colors.bgButtonTertiary, size: 24)
        }
        .frame(width: settingsBadgeDiameter, height: settingsBadgeDiameter)
        .clipShape(Circle())
    }

    private var settingsCardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: settingsCardTopRadius,
            bottomLeadingRadius: cardCornerRadius,
            bottomTrailingRadius: cardCornerRadius,
            topTrailingRadius: settingsCardTopRadius
        )
    }

    private var settingsCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("customRPCsLockedRequires".localized)
                .settingsText(.priceFootnote)
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
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    Text(
                        String(
                            format: "customRPCsLockedTierSubtitle".localized,
                            viewModel.thresholdText
                        )
                    )
                    .settingsText(.priceFootnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            settingsBalanceRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(
            settingsCardShape
                .fill(Theme.colors.bgSurface1)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private var settingsBalanceRow: some View {
        HStack(spacing: 6) {
            Icon(.walletFilled, color: Theme.colors.textTertiary, size: 16)
            Text("customRPCsLockedYourBalance".localized)
                .settingsText(.priceFootnote)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 0)
            Text(viewModel.balanceText)
                .settingsText(.priceFootnote)
                .foregroundStyle(
                    viewModel.isBelowThreshold
                        ? Theme.colors.alertWarning
                        : Theme.colors.textPrimary
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: settingsBalanceRadius)
                .fill(Theme.colors.bgSurface12)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private var settingsFooter: some View {
        Button(action: onUnlock) {
            Text("customRPCsLockedGetVult".localized)
                .font(Theme.fonts.buttonSSemibold)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: settingsFooterHeight, alignment: .bottom)
                .padding(.bottom, 19)
                .background(footerGradient)
                .overlay(footerInnerShadow)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: settingsFooterRadius,
                        bottomTrailingRadius: settingsFooterRadius
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
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
        .background(cardShape.fill(Theme.colors.bgSurface1))
        .clipShape(cardShape)
        .overlay(cardShape.stroke(Theme.colors.borderLight, lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius)
    }

    private var balanceRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Icon(.walletFilled, color: Theme.colors.textTertiary, size: 16)
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
            Theme.radius.md.shape
                .fill(Theme.colors.bgSurface12)
        )
        .overlay(
            Theme.radius.md.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    /// Gradient "Get $VULT" footer tucked behind `cardContent`'s rounded bottom
    /// and peeking below — mirroring the tier-card footer in `VultDiscountTierView`.
    /// A `Button` (not `onTapGesture` on an offset view) so the peek is reliably
    /// tappable. Renders the required tier's gradient (Silver).
    private var getVultFooter: some View {
        Button(action: onUnlock) {
            Text("customRPCsLockedGetVult".localized)
                .font(Theme.fonts.buttonSSemibold)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: footerHeight, alignment: .bottom)
                .padding(.bottom, 14)
                .background(footerGradient)
                .overlay(footerInnerShadow)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: cardCornerRadius,
                        bottomTrailingRadius: cardCornerRadius
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tier-colored footer gradient, matching the non-ultimate branch of
    /// `VultDiscountTierView.footerGradient` for the required tier.
    private var footerGradient: some View {
        LinearGradient(
            colors: [viewModel.requiredTier.secondaryColor, viewModel.requiredTier.primaryColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Soft top highlight on the footer, matching
    /// `VultDiscountTierView.footerInnerShadow`.
    private var footerInnerShadow: some View {
        footerRadius.shape
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
            .blur(radius: 1)
            .mask(
                footerRadius.shape
                    .fill(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .allowsHitTesting(false)
    }
}

#Preview {
    LockedFeatureSheet(
        feature: .customRPC,
        vault: .example,
        isPresented: .constant(true)
    ) {}
}
