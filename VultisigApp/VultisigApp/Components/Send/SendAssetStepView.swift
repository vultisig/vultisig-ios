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
    @State private var listing: Listing?

    private static let sectionSpacing: CGFloat = 12
    private static let sectionTitleTopPadding: CGFloat = 4

    var body: some View {
        let inputs = listingInputs
        // Built inline only until the first `onChange` stores it.
        let listing = self.listing ?? makeListing(inputs)
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
            self.listing = makeListing(newInputs)
        }
        // Rates live outside the coins, so a refresh arrives as this signal.
        .onReceive(RateProvider.shared.ratesDidChange) { _ in
            self.listing = makeListing(listingInputs)
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

    private func browser(_ listing: Listing) -> some View {
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

    private func results(_ listing: Listing) -> some View {
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

    private func list(_ rows: [Listing.Row]) -> some View {
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

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything the listing depends on that changes while the step is shown. Reading each coin's
    /// `rawBalance` here also re-runs the body on a balance refresh or a coin joining the vault.
    private var listingInputs: ListingInputs {
        ListingInputs(
            filter: filter,
            query: SendAssetListRule.query(from: searchText),
            selectedCoinID: selectedCoin.id,
            coins: vault.coins.map { ListingInputs.CoinBalance(id: $0.id, rawBalance: $0.rawBalance) }
        )
    }

    /// The vault's sendable coins, richest first with the selected coin on top,
    /// and the sendable chains, largest holding first. A search spans every
    /// chain; without one the chain filter applies. Each coin's fiat value is
    /// read once, in one currency, for both orders.
    private func makeListing(_ inputs: ListingInputs) -> Listing {
        let currency = SettingsCurrency.current
        let chains = vault.chains
        let sendableChains = Set(chains)
        var holdings: [Chain: Decimal] = [:]
        var rows: [Listing.Row] = []
        for coin in vault.coins where SendAssetListRule.isSendable(coin, sendableChains: sendableChains) {
            let fiat = RateProvider.shared.fiatBalance(value: coin.combinedBalanceDecimal, coin: coin, currency: currency)
            holdings[coin.chain, default: 0] += fiat
            if SendAssetListRule.matches(coin, filter: inputs.filter, query: inputs.query) {
                rows.append(Listing.Row(coin: coin, fiat: fiat))
            }
        }
        rows.sort { lhs, rhs in
            if lhs.fiat != rhs.fiat { return lhs.fiat > rhs.fiat }
            if lhs.coin.ticker != rhs.coin.ticker { return lhs.coin.ticker < rhs.coin.ticker }
            return lhs.coin.chain.index < rhs.coin.chain.index
        }
        if let selectedIndex = rows.firstIndex(where: { $0.coin.id == inputs.selectedCoinID }) {
            rows.insert(rows.remove(at: selectedIndex), at: 0)
        }
        return Listing(filter: inputs.filter, rows: rows, chains: Self.sortedByHoldings(chains, holdings: holdings))
    }

    /// Ties keep the vault's order so the row stays put until a balance changes.
    private static func sortedByHoldings(_ chains: [Chain], holdings: [Chain: Decimal]) -> [Chain] {
        chains.enumerated()
            .sorted { lhs, rhs in
                let lhsHolding = holdings[lhs.element] ?? 0
                let rhsHolding = holdings[rhs.element] ?? 0
                if lhsHolding != rhsHolding { return lhsHolding > rhsHolding }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var shouldOfferCustomToken: Bool {
        guard !trimmedQuery.isEmpty, case .chain(let chain) = filter else {
            return false
        }
        return CustomTokenResolverFactory.supports(chain: chain)
    }

    private func onTokenAdded(_ token: CoinMeta) {
        showCustomToken = false
        searchText = token.ticker
    }
}

/// Which of the vault's coins the Send asset list shows.
enum SendAssetListRule {
    /// The search text in the form the list matches against.
    static func query(from searchText: String) -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isSendable(_ coin: Coin, sendableChains: Set<Chain>) -> Bool {
        sendableChains.contains(coin.chain) && !coin.isDefiOnly
    }

    /// A search spans every chain; without one the chain filter applies.
    static func matches(_ coin: Coin, filter: SendChainFilter, query: String) -> Bool {
        guard !query.isEmpty else { return filter.includes(coin.chain) }
        return coin.ticker.lowercased().contains(query) || coin.chain.displayName.lowercased().contains(query)
    }
}

/// The asset list and carousel order, rebuilt only when their inputs change.
private struct Listing {
    struct Row {
        let coin: Coin
        let fiat: Decimal
    }

    /// The filter the rows were built for.
    let filter: SendChainFilter
    let rows: [Row]
    let chains: [Chain]
}

private struct ListingInputs: Equatable {
    struct CoinBalance: Equatable {
        let id: String
        let rawBalance: String
    }

    let filter: SendChainFilter
    let query: String
    let selectedCoinID: String
    let coins: [CoinBalance]
}
