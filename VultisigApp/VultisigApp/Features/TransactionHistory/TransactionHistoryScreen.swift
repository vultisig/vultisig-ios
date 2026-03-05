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
                chainFilterChip
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

    // MARK: - Chain Filter Chip

    @ViewBuilder
    private var chainFilterChip: some View {
        if let chainName = viewModel.chainFilterName {
            HStack {
                HStack(spacing: 6) {
                    Text(chainName)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(20)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
                    ForEach(grouped, id: \.0) { section in
                        CommonListHeaderView(title: section.0)

                        ForEach(section.1) { tx in
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
