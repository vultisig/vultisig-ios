//
//  CustomTokenScreen.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/06/24.
//

import Foundation
import SwiftUI
import WalletCore

struct CustomTokenScreen: View {
    let vault: Vault
    let chain: Chain
    @Binding var isPresented: Bool
    var onClose: () -> Void

    @StateObject private var viewModel: CustomTokenViewModel
    @StateObject private var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject private var coinViewModel: CoinSelectionViewModel

    @Environment(\.dismiss) private var dismiss

    init(vault: Vault, chain: Chain, isPresented: Binding<Bool>, onClose: @escaping () -> Void) {
        self.vault = vault
        self.chain = chain
        self._isPresented = isPresented
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: CustomTokenViewModel(vault: vault, chain: chain))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("findCustomTokens".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.title2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 12) {
                        SearchTextField(
                            value: $viewModel.contractAddress,
                            showPasteButton: true,
                            placeholder: viewModel.searchPlaceholder
                        )
                        AccessoryButton(icon: .searchArea) {
                            viewModel.search()
                        }
                    }

                    switch viewModel.searchState {
                    case .found(let token):
                        tokenInfoView(token)
                            .transition(.opacity)

                        PrimaryButton(title: String(format: "customTokenAddButton".localized, viewModel.tokenSymbol)) {
                            saveAssets()
                        }
                        .transition(.opacity)

                    case .invalid(let message, let showsRetry):
                        errorView(message: message, showsRetry: showsRetry)
                            .transition(.opacity)

                    case .idle, .loading:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.25), value: viewModel.searchState)
            }
            .crossPlatformToolbar(showsBackButton: false) {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        onClose()
                    }
                }
            }
            .onSubmit {
                viewModel.search()
            }
        }
        .onLoad {
            tokenViewModel.loadData(chain: chain, vault: vault)
        }
        .onChange(of: viewModel.contractAddress) { _, newValue in
            viewModel.validateAddress(newValue)
        }
        .withLoading(
            text: "pleaseWait".localized,
            isLoading: Binding(
                get: { viewModel.searchState == .loading },
                set: { _ in }
            )
        )
        .withLoading(text: "addingToken".localized, isLoading: $viewModel.isAddingToken)
    }

    /// Builds a banner view displaying the given error with an optional retry button.
    /// - Parameters:
    ///   - message: The user-facing error message to present.
    ///   - showsRetry: Whether to offer a retry action (hidden for rate-limit errors).
    /// - Returns: An ``ActionBannerView`` configured for the error.
    func errorView(message: String, showsRetry: Bool) -> some View {
        ActionBannerView(
            title: message,
            subtitle: "customTokenErrorSubtitle".localized,
            buttonTitle: "retry".localized,
            showsActionButton: showsRetry
        ) {
            viewModel.search()
        }
    }

    /// A card view showing the resolved custom token's icon, ticker, chain badge, and contract address.
    func tokenInfoView(_ token: CoinMeta) -> some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: token.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: token.ticker,
                    tokenChainLogo: token.tokenChainLogo
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(token.ticker)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodyMMedium)

                        Text(token.chain.name)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .font(Theme.fonts.caption10)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .overlay(Theme.radius.pill.shape.stroke(Theme.colors.borderLight))
                    }

                    Text(token.contractAddress)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.caption12)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
            GradientListSeparator()
        }
        .clipShape(Theme.radius.xl.shape)
    }

    /// Persists the resolved custom token to the vault and dismisses the screen.
    /// Shows an "adding token" loading indicator while the save is in progress.
    private func saveAssets() {
        Task {
            if await viewModel.saveAssets(coinSelectionViewModel: coinViewModel) {
                dismiss()
            }
        }
    }
}
