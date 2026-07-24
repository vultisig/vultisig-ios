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
                        CircularAccessoryIconButton(icon: .searchArea) {
                            Task {
                                await viewModel.fetchTokenInfo()
                            }
                        }
                    }

                    if let error = viewModel.error {
                        errorView(error: error)
                            .transition(.opacity)
                    }

                    if viewModel.showTokenInfo {
                        tokenInfoView

                        PrimaryButton(title: "Add \(viewModel.tokenSymbol) token") {
                            saveAssets()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.horizontal, 16)
            }
            .crossPlatformToolbar(showsBackButton: false) {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        onClose()
                    }
                }
            }
            .onSubmit {
                Task {
                    await viewModel.fetchTokenInfo()
                }
            }
        }
        .onLoad {
            tokenViewModel.loadData(chain: chain, vault: vault)
        }
        .onChange(of: viewModel.contractAddress) { _, newValue in
            viewModel.validateAddress(newValue)
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $viewModel.isLoading)
        .withLoading(text: "addingToken".localized, isLoading: $viewModel.isAddingToken)
    }

    /// Builds a banner view displaying the given error with an optional retry button.
    /// - Parameter error: The error to present. Rate-limit errors hide the retry action.
    /// - Returns: An ``ActionBannerView`` configured for the error.
    func errorView(error: Error) -> some View {
        ActionBannerView(
            title: error.localizedDescription,
            subtitle: "customTokenErrorSubtitle".localized,
            buttonTitle: "retry".localized,
            showsActionButton: !(error is RateLimitError)
        ) {
            Task { await viewModel.fetchTokenInfo() }
        }
    }

    /// A card view showing the resolved custom token's icon, ticker, chain badge, and contract address.
    var tokenInfoView: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: viewModel.token?.logo ?? .empty,
                    size: CGSize(width: 36, height: 36),
                    ticker: viewModel.token?.ticker ?? .empty,
                    tokenChainLogo: viewModel.token?.tokenChainLogo
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(viewModel.token?.ticker ?? .empty)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodyMMedium)

                        Text(viewModel.token?.chain.name ?? .empty)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .font(Theme.fonts.caption10)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.colors.borderLight))
                    }

                    Text(viewModel.token?.contractAddress ?? .empty)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.caption12)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
            GradientListSeparator()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
