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
    case externalRecipient
}

struct AdvancedSwapSheet: View {
    @Binding var isPresented: Bool
    let coin: Coin
    let isGasLimitSupported: Bool
    @Binding var settings: SwapAdvancedSettings

    @State private var sheetType: AdvancedSwapSheetType = .main
    @State private var shouldUseMoveTransition = true

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
        .animatedPresentationDetents(target: detent, alwaysAvailable: [.large])
    }

    private var detent: PresentationDetent {
        switch sheetType {
        case .main:
            return .height(isGasLimitSupported ? 330 : 260)
        case .slippage:
            return .height(520)
        case .gasLimit:
            return .height(280)
        case .externalRecipient:
            return .height(330)
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            AdvancedSwapSheetHeader(title: "advancedSwap".localized) {
                isPresented = false
            }

            VStack(spacing: 0) {
                AdvancedSwapMainRow(
                    icon: "slippage",
                    title: "slippageTolerance".localized,
                    value: settings.slippage.displayValue
                ) {
                    updateSheet(.slippage)
                }

                if isGasLimitSupported {
                    Separator()
                    AdvancedSwapMainRow(
                        icon: "gas",
                        title: "gasLimit".localized,
                        value: gasLimitValue
                    ) {
                        updateSheet(.gasLimit)
                    }
                }

                Separator()
                AdvancedSwapMainRow(
                    icon: "external-recipient",
                    title: "useExternalRecipient".localized,
                    value: externalRecipientValue
                ) {
                    updateSheet(.externalRecipient)
                }
            }
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private var gasLimitValue: String {
        settings.gasLimit.map(String.init) ?? "auto".localized
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
                Button(action: onClose) {
                    Icon(
                        named: showBack ? "chevron.left" : "x",
                        color: Theme.colors.textPrimary,
                        size: 16,
                        isSystem: showBack
                    )
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.colors.bgSurface2))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Main row

struct AdvancedSwapMainRow: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(named: icon, color: Theme.colors.textPrimary, size: 16, isSystem: false)
                Text(title)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
                Text(value)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                Icon(named: "chevron-right-small", color: Theme.colors.textTertiary, size: 20)
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
                        settings: $settings
                    )
                }
        }
    }
    return PreviewContainer()
}
