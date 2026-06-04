//
//  SwapQuotesPickerSheet.swift
//  VultisigApp
//
//  Provider-selection sheet (Silver `VultDiscountTier`+). Lists every fetched
//  swap quote best→worst by net output, tags the top row "Recommended", and lets
//  the user pick a non-best provider. The pick sets `selectedQuote`; the rest of
//  the flow (fees, rate, verify, sign) recomputes off the active `quote`. Each
//  row shows the provider logo + name on the left and the reference output
//  (`~`-prefixed, with the asset icon) + its fiat value on the right.
//

import SwiftUI

struct SwapQuotesPickerSheet: View {
    @Bindable var detailsViewModel: SwapDetailsViewModel
    @Binding var showSheet: Bool

    private var vm: SwapDetailsViewModel { detailsViewModel }

    var body: some View {
        content.sheetContainer()
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(vm.orderedPickerQuotes.enumerated()), id: \.offset) { _, quote in
                        row(for: quote)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .crossPlatformToolbar(showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    showSheet = false
                }
            }
        }
        .background(Theme.colors.bgPrimary)
        .applySheetSize()
        .sheetStyle()
    }

    private var title: some View {
        Text("swapProvidersSheetTitle".localized)
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            .multilineTextAlignment(.leading)
    }

    private func row(for quote: SwapQuote) -> some View {
        let isRecommended = vm.isBest(quote)
        return Button {
            vm.selectProvider(quote)
            showSheet = false
        } label: {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: quote.providerLogo,
                    size: CGSize(width: 28, height: 28),
                    ticker: quote.displayName ?? "",
                    tokenChainLogo: nil
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(quote.displayName ?? "")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    if isRecommended {
                        tag("swapProviderRecommended".localized, color: Theme.colors.alertSuccess)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.referenceOutput(for: quote))
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)

                        AsyncImageView(
                            logo: vm.toCoin.logo,
                            size: CGSize(width: 18, height: 18),
                            ticker: vm.toCoin.ticker,
                            tokenChainLogo: nil
                        )
                    }

                    Text(vm.referenceFiat(for: quote))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Small capsule tag with a soft glow in its own colour (Selected / Recommended).
    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(Theme.fonts.caption10)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(color.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.6), radius: 4)
    }
}

#Preview {
    SwapQuotesPickerSheet(
        detailsViewModel: SwapDetailsViewModel(),
        showSheet: .constant(true)
    )
}
