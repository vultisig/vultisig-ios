//
//  SelectRouteSettingsView.swift
//  VultisigApp
//
//  Select-route sub-sheet of the Advanced Swap sheet. Lists every fetched swap
//  quote best→worst by net output (pinning the active pick to the top), each
//  row showing the provider logo + name, a "Fee $X · ~Ns" subtitle, the output
//  amount + fiat on the right, and a radio/green-check selection indicator.
//  Tapping a route applies the manual provider override and returns to Main;
//  height + back navigation are the host sheet's responsibility.
//

import SwiftUI

struct SelectRouteSettingsView: View {
    @Bindable var detailsViewModel: SwapDetailsViewModel
    let onBack: () -> Void

    private var vm: SwapDetailsViewModel { detailsViewModel }

    var body: some View {
        VStack(spacing: 12) {
            AdvancedSwapSheetHeader(title: "selectRoute".localized, showBack: true, onClose: onBack)

            Text("selectRouteHelper".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(vm.orderedPickerQuotes.enumerated()), id: \.element.displayName) { index, quote in
                        routeRow(for: quote)
                        if index < vm.orderedPickerQuotes.count - 1 {
                            Separator()
                        }
                    }
                }
                .background(Theme.colors.bgSurface1)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func isSelected(_ quote: SwapQuote) -> Bool {
        vm.quote == quote
    }

    private func routeRow(for quote: SwapQuote) -> some View {
        let selected = isSelected(quote)
        return Button {
            vm.selectProvider(quote)
            onBack()
        } label: {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: quote.providerLogo,
                    size: CGSize(width: 36, height: 36),
                    ticker: quote.displayName ?? "",
                    tokenChainLogo: nil
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.displayName ?? "")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    feeSubtitle(for: quote, highlightFee: selected)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(vm.referenceOutput(for: quote))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(vm.referenceFiat(for: quote))
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textTertiary)
                }

                radioIndicator(isSelected: selected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? Theme.colors.alertSuccess.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Fee $X · ~Ns" subtitle. The fee amount is tinted green on the selected
    /// row (per Figma); the ETA segment is dropped when the provider doesn't
    /// expose an estimate (EVM aggregators).
    @ViewBuilder
    private func feeSubtitle(for quote: SwapQuote, highlightFee: Bool) -> some View {
        let fee = vm.routeFeeString(for: quote)
        let eta = vm.routeEtaString(for: quote)

        if fee.isEmpty && eta.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                if !fee.isEmpty {
                    Text("fee".localized + " ")
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text(fee)
                        .foregroundStyle(highlightFee ? Theme.colors.alertSuccess : Theme.colors.textTertiary)
                }
                if !fee.isEmpty && !eta.isEmpty {
                    Text(" · ")
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                if !eta.isEmpty {
                    Text(eta)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .font(Theme.fonts.footnote)
        }
    }

    private func radioIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Theme.colors.alertSuccess : Theme.colors.borderLight, lineWidth: 1.5)
                .frame(width: 16, height: 16)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
        }
    }
}

#Preview {
    SelectRouteSettingsView(detailsViewModel: SwapDetailsViewModel()) {}
}
