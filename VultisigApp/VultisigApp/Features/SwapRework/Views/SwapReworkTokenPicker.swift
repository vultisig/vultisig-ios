//
//  SwapReworkTokenPicker.swift
//  VultisigApp
//
//  The reworked token picker: recents, the vault's assets by value, chain
//  chips and the search field pinned at the bottom for thumb reach. A token
//  that claims a curated ticker at another contract needs an explicit
//  acknowledgment. Tokens the vault does not hold yet open the existing
//  catalog picker for the chosen chain.
//

import SwiftUI

struct SwapReworkTokenPicker: View {
    let title: String
    let rows: [SwapReworkPickerRow]
    let recentIDs: [String]
    let selectedID: String
    let onSelect: (SwapReworkPickerRow) -> Void
    let onBrowseCatalog: (String?) -> Void
    let onClose: () -> Void

    @State private var chainFilter: String?
    @State private var query = ""
    @State private var pendingUnverified: SwapReworkPickerRow?
    @State private var acknowledged = false

    private var filtered: [SwapReworkPickerRow] {
        SwapReworkPickerFilter.rows(rows, chainName: chainFilter, query: query)
    }

    private var recents: [SwapReworkPickerRow] {
        SwapReworkPickerFilter.recents(recentIDs, in: rows)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if query.isEmpty, chainFilter == nil, !recents.isEmpty {
                        sectionTitle("swapReworkRecent".localized)
                        recentsRow
                    }
                    sectionTitle("swapReworkYourAssets".localized)
                    VStack(spacing: 4) {
                        ForEach(filtered) { row in
                            assetRow(row)
                        }
                    }
                    browseCatalogButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            bottomBar
        }
        .background(Theme.colors.bgPrimary)
        #if DEBUG
        .onAppear {
            guard SwapReworkConfig.demoScenario == .unverified else { return }
            pendingUnverified = rows.first { $0.trust != .verified }
        }
        #endif
        .crossPlatformSheet(item: $pendingUnverified) { row in
            SwapReworkUnverifiedSheet(
                row: row,
                acknowledged: $acknowledged,
                onUseAnyway: {
                    pendingUnverified = nil
                    onSelect(row)
                },
                onPickReal: {
                    pendingUnverified = nil
                    query = row.asset.ticker
                }
            )
            .sheetStyle(padding: 0, detents: [.medium])
        }
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Theme.colors.bgSurface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("close".localized)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    private var recentsRow: some View {
        HStack(spacing: 0) {
            ForEach(recents.prefix(SwapReworkConfig.recentTokensLimit)) { row in
                Button { select(row) } label: {
                    VStack(spacing: 6) {
                        AsyncImageView(logo: row.asset.logo, size: CGSize(width: 36, height: 36), ticker: row.asset.ticker, tokenChainLogo: row.asset.chainLogo)
                        Text(row.asset.ticker)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func assetRow(_ row: SwapReworkPickerRow) -> some View {
        Button { select(row) } label: {
            HStack(spacing: 12) {
                AsyncImageView(logo: row.asset.logo, size: CGSize(width: 40, height: 40), ticker: row.asset.ticker, tokenChainLogo: row.asset.chainLogo)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.asset.ticker)
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        if case .unverified = row.trust {
                            Text("swapReworkUnverified".localized)
                                .font(Theme.fonts.caption10)
                                .foregroundStyle(Theme.colors.alertError)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.colors.alertError.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }
                    chainChip(row.asset.chainName, logo: row.asset.chainLogo ?? (row.asset.isNative ? row.asset.logo : nil))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.balanceText)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if !row.fiatText.isEmpty {
                        Text(row.fiatText)
                            .font(Theme.fonts.priceCaption)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
                .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(row.id == selectedID ? Theme.colors.bgSurface1 : .clear)
            .clipShape(Theme.radius.md.shape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapReworkPickerRow-\(row.asset.ticker)")
    }

    private func chainChip(_ name: String, logo: String?) -> some View {
        HStack(spacing: 4) {
            if let logo {
                AsyncImageView(logo: logo, size: CGSize(width: 14, height: 14), ticker: name, tokenChainLogo: nil)
            }
            Text(name)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.colors.bgSurface2)
        .clipShape(Capsule())
    }

    private var browseCatalogButton: some View {
        PrimaryButton(title: browseTitle, type: .secondary, size: .small) {
            onBrowseCatalog(chainFilter)
        }
        .padding(.top, 8)
    }

    private var browseTitle: String {
        guard let chainFilter else { return "swapReworkBrowseAll".localized }
        return String(format: "swapReworkBrowseChain".localized, chainFilter)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "swapReworkAllChains".localized, isActive: chainFilter == nil) { chainFilter = nil }
                    ForEach(SwapReworkPickerFilter.chains(rows), id: \.self) { chain in
                        filterChip(title: chain, isActive: chainFilter == chain) { chainFilter = chain }
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.colors.textTertiary)
                TextField("", text: $query, prompt: Text("swapReworkSearchPrompt".localized).foregroundStyle(Theme.colors.textTertiary))
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("swapReworkPickerSearch")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.colors.bgSurface1)
            .clipShape(Capsule())
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(Theme.colors.bgPrimary)
    }

    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(isActive ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isActive ? Theme.colors.primaryAccent4.opacity(0.24) : Theme.colors.bgSurface1)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func select(_ row: SwapReworkPickerRow) {
        if case .unverified = row.trust {
            acknowledged = false
            pendingUnverified = row
        } else {
            onSelect(row)
        }
    }
}

struct SwapReworkUnverifiedSheet: View {
    let row: SwapReworkPickerRow
    @Binding var acknowledged: Bool
    let onUseAnyway: () -> Void
    let onPickReal: () -> Void

    private var genuineContract: String {
        if case .unverified(let contract) = row.trust { return contract }
        return ""
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.alertError)
                .frame(width: 56, height: 56)
                .background(Theme.colors.alertError.opacity(0.16))
                .clipShape(Circle())
            Text("swapReworkUnverifiedTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(String(format: "swapReworkUnverifiedBody".localized, row.asset.ticker, SwapTokenTrust.shortContract(row.contract)))
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                contractRow("swapReworkUnverifiedContract".localized, SwapTokenTrust.shortContract(row.contract))
                contractRow(String(format: "swapReworkUnverifiedReal".localized, row.asset.ticker), SwapTokenTrust.shortContract(genuineContract))
            }
            Button { acknowledged.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                        .foregroundStyle(acknowledged ? Theme.colors.alertError : Theme.colors.textTertiary)
                    Text(String(format: "swapReworkUnverifiedAck".localized, row.asset.ticker))
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("swapReworkUnverifiedAck")
            HStack(spacing: 10) {
                PrimaryButton(title: "swapReworkUseAnyway".localized, type: .secondary, action: onUseAnyway)
                    .disabled(!acknowledged)
                    .opacity(acknowledged ? 1 : 0.5)
                PrimaryButton(title: String(format: "swapReworkPickReal".localized, row.asset.ticker), action: onPickReal)
            }
        }
        .padding(20)
    }

    private func contractRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
}
