//
//  TransactionHistoryScreen.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryScreen: View {
    @StateObject var viewModel: TransactionHistoryViewModel

    @Environment(\.openURL) var openURL

    init(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?) {
        _viewModel = StateObject(wrappedValue: TransactionHistoryViewModel(
            pubKeyECDSA: pubKeyECDSA,
            vaultName: vaultName,
            chainFilter: chainFilter
        ))
    }

    var body: some View {
        Screen(title: "transactionHistory".localized, edgeInsets: ScreenEdgeInsets(bottom: 0)) {
            VStack(spacing: 0) {
                tabBar
                assetFilterChips
                content
            }
        }
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .crossPlatformSheet(item: $viewModel.selectedDetail) { detail in
            detailSheet(for: detail)
        }
        .crossPlatformSheet(isPresented: $viewModel.showAssetFilter) {
            TransactionHistoryAssetFilterView(
                viewModel: viewModel,
                isPresented: $viewModel.showAssetFilter
            )
        }
        .onChange(of: viewModel.showAssetFilter) { _, isShowing in
            if !isShowing {
                viewModel.filterSearchText = ""
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: .zero) {
            SegmentedControl(
                selection: $viewModel.selectedTab,
                items: TransactionHistoryTab.allCases.map {
                    SegmentedControlItem(value: $0, title: $0.title)
                }
            )
            .fixedSize()

            Spacer()

            CircularAccessoryIconButton(icon: "magnifying-glass") {
                viewModel.showAssetFilter = true
            }
        }
    }

    // MARK: - Asset Filter Chips

    @ViewBuilder
    private var assetFilterChips: some View {
        let assets = viewModel.selectedFilterAssets
        if !assets.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(assets, id: \.ticker) { asset in
                        assetChip(asset)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.clearAssetFilters()
                    }
                } label: {
                    Text("clearFilters".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.alertInfo)
                }
            }
            .padding(.top, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func assetChip(_ asset: TransactionHistoryCoinAsset) -> some View {
        HStack(spacing: 6) {
            AsyncImageView(
                logo: asset.logo,
                size: CGSize(width: 16, height: 16),
                ticker: asset.ticker,
                tokenChainLogo: asset.chainLogo
            )

            Text("\(asset.ticker) (\(asset.network))")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)

            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(4)
                .background(Circle().fill(.black.opacity(0.22)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(6)
        .transition(.opacity.combined(with: .scale))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.removeAssetFilter(asset.ticker)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let grouped = viewModel.groupedTransactions

        ScrollView(showsIndicators: false) {
            if grouped.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.title) { section in
                        CommonListHeaderView(title: section.title, subtitle: section.subtitle)

                        ForEach(section.transactions) { tx in
                            cardView(for: tx)
                                .onTapGesture {
                                    viewModel.selectedDetail = tx
                                }
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .overlay(alignment: .bottom) {
            bottomGradient
        }
    }

    private var bottomGradient: some View {
        LinearGradient(
            colors: [
                Theme.colors.bgPrimary,
                Theme.colors.bgPrimary.opacity(0),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: 40)
        .allowsHitTesting(false)
    }

    private func cardView(for tx: TransactionHistoryData) -> some View {
        TransactionHistoryCardView(transaction: tx)
    }

    private var emptyState: some View {
        ActionBannerView(
            icon: "calendar-days",
            title: "noTransactionsYet".localized,
            subtitle: "noTransactionsYetSubtitle".localized,
            buttonTitle: "",
            showsActionButton: false,
            action: {}
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Detail Sheet

    private func detailSheet(for detail: TransactionHistoryData) -> some View {
        TransactionHistoryDetailSheet(transaction: detail)
    }
}
