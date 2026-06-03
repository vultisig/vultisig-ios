//
//  CustomRPCListScreen.swift
//  VultisigApp
//

import SwiftUI

struct CustomRPCListScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel = CustomRPCListViewModel()
    @State private var searchFocused = false

    var body: some View {
        Screen {
            VStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText, isFocused: $searchFocused)

                if viewModel.filteredRows.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .screenTitle("settingsAdvancedCustomRPC".localized)
        .onAppear {
            viewModel.reload()
        }
        .onDisappear {
            viewModel.searchText = ""
        }
    }

    var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredRows) { row in
                    Button {
                        router.navigate(to: SettingsRoute.customRPCDetail(chain: row.chain))
                    } label: {
                        CustomRPCChainRow(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var emptyState: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noResultFound")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CustomRPCChainRow: View {
    let row: CustomRPCRow

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: row.chain.logo,
                size: CGSize(width: 36, height: 36),
                ticker: row.chain.ticker,
                tokenChainLogo: row.chain.logo
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(row.chain.name)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(row.activeURL ?? "customRPCDefaultEndpoint".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            CustomRPCStatusChip(isCustom: row.isCustom)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}

struct CustomRPCStatusChip: View {
    let isCustom: Bool

    var body: some View {
        Text(isCustom ? "customRPCTagCustom".localized : "customRPCTagDefault".localized)
            .font(Theme.fonts.caption10)
            .foregroundStyle(isCustom ? Theme.colors.alertSuccess : Theme.colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.colors.bgPrimary)
            .clipShape(Capsule())
    }
}
