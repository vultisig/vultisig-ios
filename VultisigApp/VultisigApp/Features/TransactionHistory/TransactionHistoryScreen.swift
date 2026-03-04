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
