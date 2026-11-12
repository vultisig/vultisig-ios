//
//  SendAssetStepView.swift
//  VultisigApp
//

import SwiftUI

/// Inline Send asset picker: search, chain filter and the vault's coins.
struct SendAssetStepView: View {
    let vault: Vault
    let selectedCoin: Coin
    @Binding var filter: SendChainFilter
    @Binding var searchText: String
    let horizontalInset: CGFloat
    let onSelect: (Coin) -> Void

    @EnvironmentObject private var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCustomToken = false
    @State private var isSearchFocused = false
    @State private var listing: SendAssetListing?

    private static let sectionSpacing: CGFloat = 12
    private static let sectionTitleTopPadding: CGFloat = 4

    var body: some View {
        let inputs = listingInputs
        // Built inline only until the first `onChange` stores it.
        let listing = self.listing ?? SendAssetListing.make(vault: vault, inputs: inputs)
        VStack(alignment: .leading, spacing: 0) {
            SearchTextField(value: $searchText, isFocused: $isSearchFocused)
                .padding(.horizontal, horizontalInset)

            browser(listing)
                .padding(.top, Self.sectionSpacing)
                .contentShape(Rectangle())
                // Chips and rows keep their own taps; this catches the gaps and titles.
                .onTapGesture { isSearchFocused = false }
        }
        .onChange(of: inputs, initial: true) { _, newInputs in
            self.listing = SendAssetListing.make(vault: vault, inputs: newInputs)
        }
        // Rates live outside the coins, so a refresh arrives as this signal.
        .onReceive(RateProvider.shared.ratesDidChange) { _ in
            self.listing = SendAssetListing.make(vault: vault, inputs: listingInputs)
        }
        .crossPlatformSheet(isPresented: $showCustomToken) {
            if case .chain(let chain) = filter {
                CustomTokenScreen(
                    vault: vault,
                    chain: chain,
                    isPresented: $showCustomToken,
                    onClose: { showCustomToken = false },
                    onTokenAdded: onTokenAdded
                )
                .environmentObject(coinSelectionViewModel)
                .background(Theme.colors.bgPrimary)
                .applySheetSize()
                .sheetStyle(padding: 0)
            }
        }
    }

    private func browser(_ listing: SendAssetListing) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            sectionTitle("chain")
                .padding(.top, Self.sectionTitleTopPadding)
                .padding(.horizontal, horizontalInset)

            SendChainFilterCarousel(
                chains: listing.chains,
                selection: chainSelection,
                horizontalInset: horizontalInset
            )

            sectionTitle("asset")
                .padding(.top, Self.sectionTitleTopPadding)
                .padding(.horizontal, horizontalInset)

            results(listing)
                .padding(.horizontal, horizontalInset)
        }
    }

    /// Search ignores the chain filter, so picking a chain drops the query to
    /// show that chain's coins.
    private var chainSelection: Binding<SendChainFilter> {
        Binding(
            get: { filter },
            set: { newValue in
                isSearchFocused = false
                searchText = ""
                filter = newValue
            }
        )
    }

    private func results(_ listing: SendAssetListing) -> some View {
        VStack(spacing: 0) {
            if listing.rows.isEmpty {
                EmptyTokenListCard(onAddCustomToken: shouldOfferCustomToken ? { showCustomToken = true } : nil)
                    .transition(.opacity)
            } else {
                list(listing.rows)
                    .transition(.opacity)
            }
        }
        // Keyed on the rows' own filter: they land one update after `filter` changes.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: listing.filter)
    }

    private func list(_ rows: [SendAssetListing.Row]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(rows, id: \.coin.id) { row in
                let coin = row.coin
                let isSelected = coin.id == selectedCoin.id
                SwapCoinCell(
                    coin: coin.toCoinMeta(),
                    balance: coin.balanceString,
                    balanceFiat: row.fiat.formatToFiat(),
                    isSelected: isSelected
                ) {
                    isSearchFocused = false
                    onSelect(coin)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.xl.shape)
        .overlay(
            Theme.radius.xl.shape
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(key.localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    /// Everything the listing depends on that changes while the step is shown. Reading each coin's
    /// `rawBalance` here also re-runs the body on a balance refresh or a coin joining the vault.
    private var listingInputs: SendAssetListing.Inputs {
        SendAssetListing.Inputs(
            filter: filter,
            query: SendAssetListRule.query(from: searchText),
            selectedCoinID: selectedCoin.id,
            coins: vault.coins.map { SendAssetListing.Inputs.CoinBalance(id: $0.id, rawBalance: $0.rawBalance) }
        )
    }

    private var shouldOfferCustomToken: Bool {
        guard !SendAssetListRule.query(from: searchText).isEmpty, case .chain(let chain) = filter else {
            return false
        }
        return CustomTokenResolverFactory.supports(chain: chain)
    }

    private func onTokenAdded(_ token: CoinMeta) {
        showCustomToken = false
        searchText = token.ticker
    }
}
