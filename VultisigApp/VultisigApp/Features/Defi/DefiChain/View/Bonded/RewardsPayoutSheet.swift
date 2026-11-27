//
//  RewardsPayoutSheet.swift
//  VultisigApp
//
//  Opened from a bonded THORChain node card: sets the share of the node's
//  future rewards paid out to the vault in RUNE (THORChain Bond Yield).
//

import SwiftUI

struct RewardsPayoutSheet: View {
    @ObservedObject var viewModel: RewardsPayoutViewModel
    let onContinue: (KeysignReview) -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(spacing: 8) {
                payoutAsset
                payoutPercentage
            }
            nodeInfo
            PrimaryButton(title: "continue".localized, isLoading: viewModel.isPreparing) {
                Task {
                    guard let review = await viewModel.prepareReview() else { return }
                    onContinue(review)
                }
            }
            .disabled(!viewModel.canContinue)
        }
        .padding(.top, 31)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .readSize { contentHeight = $0.height }
        .presentationDetents([contentHeight > 0 ? .height(contentHeight) : .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.colors.bgPrimary)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.cancelLoad() }
        #if os(macOS)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark, action: onDismiss)
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rewardsPayout".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("rewardsPayoutDescription".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var payoutAsset: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("payoutAsset".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: viewModel.coin.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: viewModel.coin.ticker,
                    tokenChainLogo: nil
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.coin.ticker)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(viewModel.coin.chain.name)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(card)
        }
    }

    private var payoutPercentage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("payoutPercentage".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
                if viewModel.loadFailed {
                    PrimaryButton(title: "tryAgain".localized, type: .secondary, size: .small) {
                        viewModel.load()
                    }
                    .fixedSize()
                } else if viewModel.currentBps == nil {
                    ProgressView()
                } else {
                    Text("\(viewModel.selectedPercentage)%")
                        .font(Theme.fonts.priceTitle1)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
            Group {
                PercentageSliderView(percentage: $viewModel.percentage)
                PercentageButtonsStack(selectedPercentage: $viewModel.percentage)
            }
            .disabled(viewModel.currentBps == nil)
            Text(caption)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .showIf(viewModel.currentBps != nil)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(card)
    }

    private var caption: String {
        viewModel.selectedPercentage == 0
            ? "rewardsPayoutCaptionNone".localized
            : String(format: "rewardsPayoutCaption".localized, viewModel.selectedPercentage)
    }

    private var nodeInfo: some View {
        VStack(spacing: 12) {
            infoRow("nodeAddress".localized) { Text(viewModel.nodeAddress.truncatedAddress) }
            infoRow("bonded".localized) {
                HiddenBalanceText(viewModel.coin.formatWithTicker(value: viewModel.bondedAmount))
            }
            infoRow("nextReward".localized) {
                HiddenBalanceText(viewModel.coin.formatWithTicker(value: viewModel.nextReward))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func infoRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            value()
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.bodySMedium)
    }

    private var card: some View {
        Theme.radius.xl.shape
            .fill(Theme.colors.bgSurface1)
            .overlay(Theme.radius.xl.shape.stroke(Theme.colors.borderLight, lineWidth: 1))
    }
}
