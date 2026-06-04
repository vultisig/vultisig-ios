//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {

    @Bindable var detailsViewModel: SwapDetailsViewModel

    @State private var showFees: Bool = true
    @State private var showQuotesSheet: Bool = false

    private var vm: SwapDetailsViewModel { detailsViewModel }

    private var hasExpandableFees: Bool {
        vm.showGas ||
        !vm.baseAffiliateFee.isEmpty ||
        !outboundFeeString.isEmpty ||
        !vm.vultDiscount.isEmpty ||
        !vm.referralDiscount.isEmpty ||
        !vm.priceImpactString.isEmpty
    }

    /// Hide the entire Provider + fees block while a quote error is on screen
    /// (the tooltip already surfaces the error). Keep it visible during loading
    /// so placeholders still appear, and whenever a valid quote is available.
    private var isBlockVisible: Bool {
        detailsViewModel.error == nil || detailsViewModel.isLoadingQuotes
    }

    var body: some View {
        content
    }

    var content: some View {
        VStack(spacing: 16) {
            if isBlockVisible {
                if let providerName = vm.quote?.displayName {
                    providerRow(providerName: providerName)
                }

                if vm.showTotalFees {
                    if hasExpandableFees {
                        ExpandableView(isExpanded: $showFees) {
                            totalFeesLabel()
                        } content: {
                            HStack {
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundStyle(Theme.colors.primaryAccent4)

                                expandableFees
                            }
                            .padding(.top, 16)
                        }
                    } else {
                        totalFeesLabel(showChevron: false)
                    }
                }
            }
        }
        .padding(.top, 8)
        .crossPlatformSheet(isPresented: $showQuotesSheet) {
            SwapQuotesPickerSheet(detailsViewModel: detailsViewModel, showSheet: $showQuotesSheet)
        }
    }

    /// The Provider row. When provider selection is available (feature flag +
    /// Silver+ AND more than one quote), it becomes tappable with a chevron that
    /// opens the picker sheet. Otherwise it stays the static read-only row — the
    /// exact behavior shipped today.
    @ViewBuilder
    private func providerRow(providerName: String) -> some View {
        if vm.canSelectProvider {
            Button {
                #if os(iOS)
                hideKeyboard()
                #endif
                showQuotesSheet = true
            } label: {
                HStack {
                    providerCell(providerName: providerName)
                    Icon(
                        named: "chevron-down-small",
                        color: Theme.colors.textSecondary,
                        size: 12
                    )
                    .rotationEffect(.degrees(-90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            providerCell(providerName: providerName)
        }
    }

    /// Provider summary cell — mirrors `getSummaryCell` but shows the provider's
    /// brand logo to the left of the name.
    private func providerCell(providerName: String) -> some View {
        HStack(spacing: 8) {
            Text("provider".localized)
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            if let logo = vm.quote?.providerLogo {
                AsyncImageView(
                    logo: logo,
                    size: CGSize(width: 16, height: 16),
                    ticker: providerName,
                    tokenChainLogo: nil
                )
            }

            Text(providerName)
                .foregroundStyle(Theme.colors.textSecondary)
                .redacted(reason: detailsViewModel.isLoading ? .placeholder : [])
        }
        .font(Theme.fonts.caption12)
    }

    private func totalFeesLabel(showChevron: Bool = true) -> some View {
        HStack {
            getSummaryCell(
                leadingText: "totalFee",
                trailingText: "\(vm.totalFeeString)"
            )

            if showChevron {
                chevron
            }
        }
    }

    var chevron: some View {
        Icon(
            named: "chevron-down-small",
            color: Theme.colors.textSecondary,
            size: 12
        )
        .rotationEffect(Angle(degrees: showFees ? 180 : 0))
        .animation(.easeInOut, value: showFees)
    }

    var expandableFees: some View {
        VStack(spacing: 16) {
            if vm.showGas {
                swapGas
            }

            if !vm.baseAffiliateFee.isEmpty {
                affiliateFee
            }

            if !outboundFeeString.isEmpty {
                outboundFee
            }

            if !vm.vultDiscount.isEmpty {
                vultDiscount
            }

            if !vm.referralDiscount.isEmpty {
                referralDiscount
            }

            if !vm.priceImpactString.isEmpty {
                priceImpact
            }
        }
    }

    var swapGas: some View {
        let gasString = vm.swapGasString
        // Only show approval fee suffix when approval is required and fee is non-zero (using numeric check)
        let showApproveFee = vm.isApproveRequired && !vm.isApproveFeeZero
        let approveFeeString = vm.approveFeeString
        let trailingText = showApproveFee ? "\(gasString) (\(approveFeeString))" : gasString
        return getSummaryCell(
            leadingText: "networkFee",
            trailingText: trailingText
        )
    }

    var affiliateFee: some View {
        HStack {
            Text(vm.swapFeeLabel)
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(vm.baseAffiliateFee)
                .foregroundColor(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.caption12)
    }

    var vultDiscount: some View {
        HStack {
            vultTierIcon

            Text(vm.vultDiscountLabel)
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(vm.vultDiscount)
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    @ViewBuilder
    private var vultTierIcon: some View {
        if let tier = VultDiscountTier.from(bpsDiscount: vm.vultDiscountBps) {
            Image(tier.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "star.circle.fill")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.turquoise)
        }
    }

    var outboundFee: some View {
        getSummaryCell(
            leadingText: "swap.outbound_fee",
            trailingText: outboundFeeString
        )
    }

    var referralDiscount: some View {
        HStack {
            Image(systemName: "megaphone.fill")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.primaryAccent4)

            Text(vm.referralDiscountLabel)
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(vm.referralDiscount)
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    var priceImpact: some View {
        HStack {
            Text(NSLocalizedString("swap.price_impact", comment: "Price Impact"))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(vm.priceImpactString)
                .foregroundColor(vm.priceImpactColor)
        }
        .font(Theme.fonts.caption12)
    }

    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(trailingText)
                .foregroundColor(Theme.colors.textSecondary)
                .redacted(reason: detailsViewModel.isLoading ? .placeholder : [])
        }
        .font(Theme.fonts.caption12)
    }

    private func getImage(_ image: String) -> some View {
        Image(image)
            .resizable()
            .frame(width: 16, height: 16)
    }

    private func getErrorCell(text: String) -> some View {
        HStack {
            Text(text)
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.caption12)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            Spacer()
        }
    }

    private var outboundFeeString: String {
        guard let quote = vm.quote else { return .empty }

        var outboundFeeString: String?
        let feeDecimals: Int = 8 // Default to 8 (THORChain standard)

        switch quote {
        case .thorchain(let q), .thorchainChainnet(let q), .thorchainStagenet(let q), .mayachain(let q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }

        guard let outboundFeeString = outboundFeeString else {
            return .empty
        }
        let feeAmount = outboundFeeString.toDecimal()

        // Fee is in output asset
        let feeCoin = vm.toCoin
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)

        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
}

#Preview {
    ZStack {
        Background()
        SwapDetailsSummary(detailsViewModel: SwapDetailsViewModel())
    }
}
