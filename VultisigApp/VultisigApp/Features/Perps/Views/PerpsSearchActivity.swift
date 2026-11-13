//
//  PerpsSearchActivity.swift
//  VultisigApp
//
//  Perps 9.08-9.10: market search, activity, and the shared status
//  sheet (used for "Stop loss not placed").
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "perps-activity")

// MARK: - Search

@MainActor
final class PerpsSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var markets: [PerpsMarket] = []

    private let repository: PerpsRepository

    init(repository: PerpsRepository = PerpsRepositories.make()) {
        self.repository = repository
    }

    /// Busiest first; matches on the symbol.
    var results: [PerpsMarket] {
        let sorted = markets.sorted { $0.dayVolume > $1.dayVolume }
        let text = query.trimmingCharacters(in: .whitespaces).uppercased()
        return text.isEmpty ? sorted : sorted.filter { $0.coin.uppercased().contains(text) }
    }

    func load() async {
        do {
            markets = try await repository.markets()
        } catch {
            logger.error("Perps search load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct PerpsSearchScreen: View {
    let vault: Vault

    @StateObject private var viewModel = PerpsSearchViewModel()
    @Environment(\.router) private var router

    var body: some View {
        Screen {
            VStack(spacing: 14) {
                SearchTextField(value: $viewModel.query, accessibilityIdentifier: "perpsSearchField")
                ScrollView(showsIndicators: false) {
                    if viewModel.results.isEmpty && !viewModel.markets.isEmpty {
                        Text("perpsNoMarketsFound".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .padding(.top, 24)
                    } else {
                        PerpsCard {
                            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, market in
                                if index > 0 { Separator(color: Theme.colors.borderLight, opacity: 1) }
                                Button {
                                    router.navigate(to: PerpsRoute.market(vault: vault, coin: market.coin))
                                } label: {
                                    PerpsMarketListRow(market: market)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .screenTitle("perpsMarketsTitle".localized)
        .perpsScreenMargins()
        .task { await viewModel.load() }
    }
}

// MARK: - Activity

@MainActor
final class PerpsActivityViewModel: ObservableObject {
    @Published private(set) var sections: [(day: Date, items: [PerpsActivityItem])] = []
    @Published private(set) var isLoading = true

    private let repository: PerpsRepository

    init(repository: PerpsRepository = PerpsRepositories.make()) {
        self.repository = repository
    }

    func load(vault: Vault) async {
        defer { isLoading = false }
        guard let address = PerpsConfig.tradingAccountAddress(vault: vault) else { return }
        do {
            let account = try await repository.account(address: address)
            let items = try await repository.activity(address: address, fills: account.fills)
            let calendar = Calendar.current
            sections = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
                .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.day > $1.day }
        } catch {
            logger.error("Perps activity load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct PerpsActivityScreen: View {
    let vault: Vault

    @StateObject private var viewModel = PerpsActivityViewModel()
    @State private var showsAll = false

    /// First view shows about eight rows; "See all" shows the rest.
    private static let firstViewLimit = 8

    private var visibleSections: [(day: Date, items: [PerpsActivityItem])] {
        guard !showsAll else { return viewModel.sections }
        var remaining = Self.firstViewLimit
        return viewModel.sections.compactMap { section in
            guard remaining > 0 else { return nil }
            let items = Array(section.items.prefix(remaining))
            remaining -= items.count
            return (section.day, items)
        }
    }

    private var hasMore: Bool { viewModel.sections.reduce(0) { $0 + $1.items.count } > Self.firstViewLimit }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.sections.isEmpty && !viewModel.isLoading {
                        Text("perpsNoActivity".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                    ForEach(visibleSections, id: \.day) { section in
                        Text(dayTitle(section.day))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        PerpsCard {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Separator(color: Theme.colors.borderLight, opacity: 1) }
                                PerpsActivityRow(item: item)
                            }
                        }
                    }
                    if hasMore && !showsAll {
                        PrimaryButton(title: "perpsSeeAll".localized, type: .secondary) { showsAll = true }
                            .accessibilityIdentifier("perpsActivitySeeAll")
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .screenTitle("perpsActivity".localized)
        .perpsScreenMargins()
        .task { await viewModel.load(vault: vault) }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "perpsTodayTitle".localized }
        if Calendar.current.isDateInYesterday(day) { return "perpsYesterday".localized }
        return Self.dayFormatter.string(from: day)
    }

    /// "Wed 12 Nov".
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}

struct PerpsActivityRow: View {
    let item: PerpsActivityItem

    var body: some View {
        HStack(spacing: 12) {
            PerpsCoinBadge(coin: item.coin, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer(minLength: 8)
            Text(amountText)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(amountColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var amountText: String {
        item.isSigned ? PerpsFormat.usd(item.amount, signed: true) : PerpsFormat.usd(item.amount)
    }

    private var amountColor: Color {
        guard item.isSigned, item.kind == .trade else { return Theme.colors.textPrimary }
        return item.amount >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError
    }
}

// MARK: - Status

/// One outcome, one next action.
struct PerpsStatusSheet: View {
    let title: String
    let message: String
    let row: PerpsReviewRow?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PerpsSheetTitle(title: title)
            Text(message)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let row {
                PerpsCard { PerpsRow(title: row.label, value: row.value) }
            }
            PrimaryButton(title: actionTitle, action: action)
                .accessibilityIdentifier("perpsStatusAction")
        }
        .perpsSheetChrome()
    }
}
