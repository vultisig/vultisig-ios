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
                    ForEach(Array(vm.allQuotes.enumerated()), id: \.offset) { _, quote in
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
        let isSelected = vm.isSelected(quote)
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

                HStack(spacing: 8) {
                    Text(quote.displayName ?? "")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    if isRecommended {
                        recommendedTag
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

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.primaryAccent4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recommendedTag: some View {
        Text("swapProviderRecommended".localized)
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.colors.primaryAccent4.opacity(0.16))
            .clipShape(Capsule())
    }
}

#Preview {
    SwapQuotesPickerSheet(
        detailsViewModel: SwapDetailsViewModel(),
        showSheet: .constant(true)
    )
}
