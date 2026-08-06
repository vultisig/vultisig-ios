//
//  AdvancedSwapSheet.swift
//  VultisigApp
//
//  One sheet with internal sub-states (Main / Slippage / Gas Limit / External
//  Recipient), mirroring `VaultManagementSheet`'s `sheetType` + switch +
//  `.transition` pattern and using `animatedPresentationDetents` for the height
//  changes between states. Settings are bound to the swap details view model.
//

import SwiftUI

private enum AdvancedSwapSheetType: Equatable {
    case main
    case slippage
    case gasLimit
    case selectRoute
    case externalRecipient
}

struct AdvancedSwapSheet: View {
    @Binding var isPresented: Bool
    let coin: Coin
    let isGasLimitSupported: Bool
    @Binding var settings: SwapAdvancedSettings
    @Bindable var detailsViewModel: SwapDetailsViewModel

    @State private var sheetType: AdvancedSwapSheetType = .main
    @State private var shouldUseMoveTransition = true

    private var vm: SwapDetailsViewModel { detailsViewModel }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch sheetType {
                case .main:
                    mainView
                        .transition(transition(forward: false))
                case .slippage:
                    SlippageSettingsView(slippage: $settings.slippage) {
                        updateSheet(.main)
                    }
                    .transition(transition(forward: true))
                case .gasLimit:
                    GasLimitSettingsView(gasLimit: $settings.gasLimit) {
                        updateSheet(.main)
                    }
                    .transition(transition(forward: true))
                case .selectRoute:
                    SelectRouteSettingsView(detailsViewModel: detailsViewModel) {
                        updateSheet(.main)
                    }
                    .transition(transition(forward: true))
                case .externalRecipient:
                    ExternalRecipientSettingsView(
                        coin: coin,
                        recipient: $settings.externalRecipient
                    ) {
                        updateSheet(.main)
                    }
                    .transition(transition(forward: true))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDragIndicator(.visible)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
        .animatedPresentationDetents(target: detent, alwaysAvailable: [.medium])
    }

    private var detent: PresentationDetent {
        switch sheetType {
        case .main:
            return .height(mainDetentHeight)
        case .slippage:
            return .height(520)
        case .gasLimit:
            return .height(280)
        case .selectRoute:
            return .height(559)
        case .externalRecipient:
            return .height(330)
        }
    }

    private var mainDetentHeight: CGFloat {
        Self.mainDetentHeight(
            isGasLimitSupported: isGasLimitSupported,
            canSelectProvider: vm.canSelectProvider,
            isSecuredMint: vm.isSecuredMint
        )
    }

    /// Fixed heights the main state is built from. The detent sizes the content
    /// area — the system adds the bottom safe area on top of it — so everything
    /// the card needs has to be accounted for here, the inset below it included:
    /// content is top-aligned, so anything that doesn't fit is clipped by the
    /// sheet edge rather than compressed.
    enum MainLayout {
        /// The header, plus headroom. The header itself measures 76pt; the rest
        /// absorbs a row wrapping onto a second line, which a long title does in
        /// several locales (and in English once the External Recipient row shows
        /// an address). Unused headroom only ever becomes extra space below the
        /// card, so it's cheaper than clipping the card when a row grows.
        static let chrome: CGFloat = 120
        /// One `AdvancedSwapMainRow` — 68pt on one line — plus its 1pt separator.
        static let rowHeight: CGFloat = 70
        /// The card's inset from the sheet's edges — the same value on the sides
        /// and below, so the card reads as inset rather than clipped by the
        /// sheet edge.
        static let cardInset: CGFloat = 16
    }

    /// Rows the card renders. Mirrors the conditions in `mainView` and has to
    /// stay in step with them: Slippage is always shown, Gas Limit is EVM-only,
    /// Select route needs more than one quote to pick from, and a secured mint
    /// drops External Recipient.
    static func mainRowCount(
        isGasLimitSupported: Bool,
        canSelectProvider: Bool,
        isSecuredMint: Bool
    ) -> Int {
        var rows = 1
        if isGasLimitSupported { rows += 1 }
        if canSelectProvider { rows += 1 }
        if !isSecuredMint { rows += 1 }
        return rows
    }

    /// Main-sheet height: fixed chrome, one row per row the card actually
    /// renders, and the inset that keeps the card off the sheet's bottom edge.
    static func mainDetentHeight(
        isGasLimitSupported: Bool,
        canSelectProvider: Bool,
        isSecuredMint: Bool
    ) -> CGFloat {
        let rows = mainRowCount(
            isGasLimitSupported: isGasLimitSupported,
            canSelectProvider: canSelectProvider,
            isSecuredMint: isSecuredMint
        )
        return MainLayout.chrome + CGFloat(rows) * MainLayout.rowHeight + MainLayout.cardInset
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            AdvancedSwapSheetHeader(title: "advancedSwap".localized) {
                isPresented = false
            }

            VStack(spacing: 0) {
                AdvancedSwapMainRow(
                    icon: .bolt,
                    title: "slippageTolerance".localized,
                    value: settings.slippage.displayValue
                ) {
                    updateSheet(.slippage)
                }

                if isGasLimitSupported {
                    Separator()
                    AdvancedSwapMainRow(
                        icon: .gasPump,
                        title: "gasLimit".localized,
                        value: gasLimitValue
                    ) {
                        updateSheet(.gasLimit)
                    }
                }

                if vm.canSelectProvider {
                    Separator()
                    AdvancedSwapMainRow(
                        icon: .branchOut,
                        title: "selectRoute".localized,
                        value: selectRouteValue
                    ) {
                        updateSheet(.selectRoute)
                    }
                }

                // A secured mint always deposits to the vault's own THORChain
                // address (the SECURE+ memo target); an external recipient has no
                // meaning and is ignored by the mint builder, so don't offer it.
                if !vm.isSecuredMint {
                    Separator()
                    AdvancedSwapMainRow(
                        icon: .clone2,
                        title: "useExternalRecipient".localized,
                        value: externalRecipientValue
                    ) {
                        updateSheet(.externalRecipient)
                    }
                }
            }
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.xl.shape)
            .overlay(
                Theme.radius.xl.shape
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .padding(.horizontal, MainLayout.cardInset)
            .padding(.bottom, MainLayout.cardInset)
        }
    }

    private var gasLimitValue: String {
        settings.gasLimit.map(String.init) ?? "auto".localized
    }

    /// "Auto" until the user manually overrides the route; then the picked
    /// provider's name. A refresh clears the override, so this reverts to "Auto".
    private var selectRouteValue: String {
        guard let selected = vm.selectedQuote?.displayName else { return "auto".localized }
        return selected
    }

    private var externalRecipientValue: String {
        if let recipient = settings.externalRecipient, !recipient.isEmpty {
            return recipient.truncatedAddress
        }
        return "off".localized
    }

    private func transition(forward: Bool) -> AnyTransition {
        guard shouldUseMoveTransition else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .trailing : .leading).combined(with: .opacity)
        )
    }

    private func updateSheet(_ newType: AdvancedSwapSheetType) {
        shouldUseMoveTransition = true
        withAnimation(.interpolatingSpring) {
            sheetType = newType
        }
    }
}

// MARK: - Shared header

struct AdvancedSwapSheetHeader: View {
    let title: String
    var showBack: Bool = false
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            HStack {
                ToolbarButton(image: showBack ? .chevronLeft : .xmark, type: .outline, action: onClose)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Main row

struct AdvancedSwapMainRow: View {
    let icon: ImageResource
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(icon, color: Theme.colors.textPrimary, size: 16)
                Text(title)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
                Text(value)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                Icon(.chevronRightSmall, color: Theme.colors.textTertiary, size: 20)
            }
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var isPresented = true
        @State var settings = SwapAdvancedSettings.default

        var body: some View {
            Color.clear
                .crossPlatformSheet(isPresented: $isPresented) {
                    AdvancedSwapSheet(
                        isPresented: $isPresented,
                        coin: .example,
                        isGasLimitSupported: true,
                        settings: $settings,
                        detailsViewModel: SwapDetailsViewModel()
                    )
                }
        }
    }
    return PreviewContainer()
}
