//
//  CoinDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import Combine
import Foundation

final class CoinDetailViewModel: ObservableObject {
    let coin: Coin

    @Published var availableActions: [CoinAction] = []
    private let actionResolver = CoinActionResolver()

    // Tron resources (only allocated for Tron chains)
    let tronLoader: TronResourcesLoader?
    var isTron: Bool { coin.chain == .tron }

    // MARK: - Market data

    /// Whether this coin has a CoinGecko source at all. Resolved once, up
    /// front, so the screen can leave the chart and stats out of the layout
    /// entirely for pool-priced assets rather than rendering a box that never
    /// fills.
    let supportsMarketData: Bool

    @Published private(set) var chart: MarketChart?
    @Published private(set) var stats: CoinMarketStats?
    @Published private(set) var isLoadingChart = false
    /// `true` once a chart load has finished, whatever the outcome. Until then
    /// the screen shows its placeholder instead of concluding the chart is
    /// unavailable.
    @Published private(set) var hasAttemptedChartLoad = false
    @Published private(set) var selectedRange: MarketChartRange = .day

    private let marketDataService: MarketDataServiceProtocol
    private var chartTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    /// Currency the displayed data was fetched in, so a change made in Settings
    /// is picked up the next time the sheet opens.
    private var loadedCurrency: SettingsCurrency?

    private var cancellables = Set<AnyCancellable>()

    init(
        coin: Coin,
        marketDataService: MarketDataServiceProtocol = MarketDataService.shared
    ) {
        self.coin = coin
        self.marketDataService = marketDataService
        self.supportsMarketData = MarketDataService.resolveSource(for: coin.toCoinMeta()) != nil
        self.tronLoader = coin.chain == .tron ? TronResourcesLoader(address: coin.address) : nil

        tronLoader?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setup() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: coin.chain).filtered
        }

        Task { @MainActor in
            loadMarketDataIfNeeded()
        }
    }

    /// Loads chart + stats on first open, and again when the display currency
    /// changed since the last load. Repeat calls in the same currency are
    /// no-ops: the screen's `.task` and `.onAppear` both fire on open, and the
    /// `TTLCache` behind the service would coalesce them anyway.
    @MainActor
    func loadMarketDataIfNeeded() {
        guard supportsMarketData else { return }

        let currency = SettingsCurrency.current
        guard loadedCurrency != currency else { return }

        loadedCurrency = currency
        loadChart(range: selectedRange, currency: currency)
        loadStats(currency: currency)
    }

    /// Switches the visible range.
    ///
    /// The in-flight load is cancelled, but the current series is deliberately
    /// left on screen — dimmed via `isLoadingChart` — so the layout never
    /// collapses to a spinner and back. A picker that flashes empty on every
    /// tap reads as broken even when it is fast.
    @MainActor
    func selectRange(_ range: MarketChartRange) {
        guard range != selectedRange else { return }

        selectedRange = range
        loadChart(range: range, currency: loadedCurrency ?? SettingsCurrency.current)
    }

    /// Change over the window currently on screen, as a fraction
    /// (`0.05` = +5%).
    ///
    /// Prefers the chart's own endpoints so the number always describes the
    /// line the user is looking at; falls back to the 24h figure from the
    /// market snapshot when there is no chart to describe.
    var displayedChangeFraction: Double? {
        if let fraction = chart?.changeFraction {
            return fraction
        }
        return stats?.priceChangePercentage24h.map { $0 / 100 }
    }

    var isChangePositive: Bool {
        (displayedChangeFraction ?? 0) >= 0
    }

    /// Whether the chart block belongs in the layout at all. Pool-priced assets
    /// and series too sparse to draw take the whole block out rather than
    /// leaving a gap.
    var showsChartSection: Bool {
        guard supportsMarketData else { return false }
        return chart != nil || !hasAttemptedChartLoad
    }

    // MARK: - Loading

    @MainActor
    private func loadChart(range: MarketChartRange, currency: SettingsCurrency) {
        chartTask?.cancel()
        isLoadingChart = true

        let coinMeta = coin.toCoinMeta()
        chartTask = Task { @MainActor [weak self, marketDataService] in
            let result = await marketDataService.chart(
                for: coinMeta,
                range: range,
                currency: currency
            )

            guard !Task.isCancelled, let self else { return }
            // A slow answer for a range the user has since moved away from must
            // not overwrite the newer one.
            guard self.selectedRange == range else { return }

            self.chart = result
            self.hasAttemptedChartLoad = true
            self.isLoadingChart = false
        }
    }

    @MainActor
    private func loadStats(currency: SettingsCurrency) {
        statsTask?.cancel()

        let coinMeta = coin.toCoinMeta()
        statsTask = Task { @MainActor [weak self, marketDataService] in
            let result = await marketDataService.stats(for: coinMeta, currency: currency)

            guard !Task.isCancelled else { return }
            self?.stats = result
        }
    }
}
