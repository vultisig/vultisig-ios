//
//  WidgetWatchlistSettingsScreen.swift
//  VultisigApp
//

import SwiftUI

struct WidgetWatchlistSettingsScreen: View {
    @StateObject private var viewModel = WidgetWatchlistSettingsViewModel()

    var body: some View {
        Screen {
            VStack(spacing: 14) {
                selectionSummary
                searchField
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        partialLoadError
                            .showIf(viewModel.loadFailed && !viewModel.assets.isEmpty)
                        searchStatus
                        assetSection
                    }
                }
            }
        }
        .screenTitle("watchlist".localized)
        .screenEdgeInsets(.init(bottom: 0))
        .withLoading(isLoading: $viewModel.isLoading)
        .task { await viewModel.load() }
    }

    private var partialLoadError: some View {
        HStack(spacing: 12) {
            Text("widgetWatchlistLoadError".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)

            Spacer(minLength: 8)

            PrimaryButton(title: "retry".localized, type: .secondary, size: .mini) {
                Task { await viewModel.load(force: true) }
            }
            .fixedSize()
        }
        .padding(16)
        .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
        .overlay(Theme.radius.xl.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: "widgetWatchlistSelectionCount".localized,
                    viewModel.selectionCount,
                    WidgetSharedStorage.maximumWatchlistAssets
                )
            )
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Theme.colors.textPrimary)

            Text("widgetWatchlistDescription".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        SearchTextField(value: $viewModel.searchText)
    }

    @ViewBuilder
    private var searchStatus: some View {
        if viewModel.searchFailed && viewModel.filteredAssets.isEmpty {
            Text("widgetWatchlistLoadError".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if viewModel.searchFailed {
            Text("widgetWatchlistLoadError".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }

    @ViewBuilder
    private var assetSection: some View {
        let assets = viewModel.filteredAssets

        VStack(alignment: .leading, spacing: 12) {
            Text("widgetWatchlistAssets".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            if assets.isEmpty {
                statusView
                    .commonListContainer()
            } else {
                LazyVStack(spacing: .zero) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        assetRow(asset)
                            .commonListItemContainer(index: index, itemsCount: assets.count)
                    }
                }
                .commonListContainer()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if viewModel.loadFailed {
            VStack(spacing: 12) {
                Text("widgetWatchlistLoadError".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .multilineTextAlignment(.center)

                PrimaryButton(title: "retry".localized, type: .secondary, size: .small) {
                    Task { await viewModel.load(force: true) }
                }
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else if showsEmptySearchResult {
            Text("noResultFound".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private var showsEmptySearchResult: Bool {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty &&
            !viewModel.isSearching &&
            !viewModel.searchFailed
    }

    private func assetRow(_ asset: WidgetWatchlistAsset) -> some View {
        let selected = viewModel.isSelected(asset)
        let selection = Binding(
            get: { viewModel.isSelected(asset) },
            set: { viewModel.setSelected($0, asset: asset) }
        )

        return HStack(spacing: 12) {
            AsyncImageView(
                logo: viewModel.iconLogo(for: asset),
                size: CGSize(width: 36, height: 36),
                ticker: asset.symbol,
                tokenChainLogo: nil
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.symbol)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                Text(asset.name)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VultiToggle(isOn: selection)
                .fixedSize()
                .disabled(!selected && !viewModel.canSelectMore)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    WidgetWatchlistSettingsScreen()
}
#endif
