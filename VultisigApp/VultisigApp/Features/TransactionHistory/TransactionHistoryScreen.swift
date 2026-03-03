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
        Screen(title: "transactionHistory".localized) {
            VStack(spacing: 0) {
                tabBar
                chainFilterChip
                content
            }
        }
        .onAppear {
            viewModel.load()
        }
        .sheet(item: $viewModel.selectedDetail) { detail in
            detailSheet(for: detail)
        }
        .sheet(isPresented: $viewModel.showAssetFilter) {
            TransactionHistoryAssetFilterView(viewModel: viewModel)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TransactionHistoryTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }

            Spacer()

            filterButton
        }
        .padding(.horizontal, 16)
    }

    private func tabItem(_ tab: TransactionHistoryTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(tab.title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(
                        viewModel.selectedTab == tab
                            ? Theme.colors.textPrimary
                            : Theme.colors.textTertiary
                    )

                Rectangle()
                    .fill(
                        viewModel.selectedTab == tab
                            ? Theme.colors.primaryAccent4
                            : Color.clear
                    )
                    .frame(height: 2)
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var filterButton: some View {
        Button {
            viewModel.showAssetFilter = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(
                    viewModel.selectedAssetFilters.isEmpty
                        ? Theme.colors.textTertiary
                        : Theme.colors.primaryAccent4
                )
        }
        .buttonStyle(.plain)
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

        if grouped.isEmpty {
            emptyState
        } else {
            ScrollView {
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
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func cardView(for tx: TransactionHistoryData) -> some View {
        if tx.status == .inProgress {
            TransactionHistoryInProgressCardView(transaction: tx)
        } else {
            TransactionHistoryCardView(transaction: tx)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Theme.colors.textTertiary)
            Text("noTransactionsYet".localized)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Sheet

    @ViewBuilder
    private func detailSheet(for detail: TransactionHistoryData) -> some View {
        if detail.type == .swap {
            TransactionHistorySwapDetailSheet(transaction: detail)
        } else {
            TransactionHistorySendDetailSheet(transaction: detail)
        }
    }
}
