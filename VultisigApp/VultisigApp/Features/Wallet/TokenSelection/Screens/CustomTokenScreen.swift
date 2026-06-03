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

    @State private var contractAddress: String = ""
    @State private var tokenName: String = ""
    @State private var tokenSymbol: String = ""
    @State private var tokenDecimals: Int = 0
    @State private var showTokenInfo: Bool = false
    @State var isAddingToken: Bool = false
    @State var isLoading: Bool = false
    @State var error: Error?

    @State private var isValidAddress: Bool = false
    @State private var token: CoinMeta? = nil

    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel

    @Environment(\.dismiss) var dismiss

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
                            value: $contractAddress,
                            showPasteButton: true,
                            placeholder: searchPlaceholder
                        )
                        CircularAccessoryIconButton(icon: "search-menu") {
                            Task {
                                await fetchTokenInfo()
                            }
                        }
                    }

                    if let error = error {
                        errorView(error: error)
                            .transition(.opacity)
                    }

                    if showTokenInfo {
                        tokenInfoView

                        PrimaryButton(title: "Add \(tokenSymbol) token") {
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
                    ToolbarButton(image: "x") {
                        onClose()
                    }
                }
            }
            .onSubmit {
                Task {
                    await fetchTokenInfo()
                }
            }
        }
        .onLoad {
            tokenViewModel.loadData(chain: chain, vault: vault)
        }
        .onChange(of: contractAddress) { _, newValue in
            validateAddress(newValue)
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isLoading)
        .withLoading(text: "addingToken".localized, isLoading: $isAddingToken)
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
            Task { await fetchTokenInfo() }
        }
    }

    /// A card view showing the resolved custom token's icon, ticker, chain badge, and contract address.
    var tokenInfoView: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: token?.logo ?? .empty,
                    size: CGSize(width: 36, height: 36),
                    ticker: token?.ticker ?? .empty,
                    tokenChainLogo: token?.chain.logo
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(token?.ticker ?? .empty)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodyMMedium)

                        Text(token?.chain.name ?? .empty)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .font(Theme.fonts.caption10)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.colors.borderLight))
                    }

                    Text(token?.contractAddress ?? .empty)
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

    /// Looks up token metadata for the current ``contractAddress`` by dispatching to the appropriate
    /// chain-specific service (THORChain bank denom, Cardano, EVM, Solana, Tron, or TON). On success,
    /// populates the token preview; on failure, sets the ``error`` state.
    private func fetchTokenInfo() async {
        guard !contractAddress.isEmpty else { return }

        // Validate address format before making API calls
        guard isValidAddress else {
            error = InvalidAddressError()
            return
        }

        isLoading = true
        showTokenInfo = false
        error = nil

        do {
            if chain == .thorChain {

                // THORChain tokens are Cosmos bank denoms (e.g. `thor.lqdy`), resolved
                // via the bank-denom metadata path — independent of any L1 pool. The
                // resolver normalizes `THOR.{SYMBOL}` to the lowercase denom and prefers
                // a curated TokensStore entry for the logo and price provider.
                let coinMeta = try await ThorchainCustomTokenResolver.resolve(input: contractAddress)
                self.token = coinMeta
                self.tokenName = coinMeta.ticker
                self.tokenSymbol = coinMeta.ticker
                self.tokenDecimals = coinMeta.decimals
                self.showTokenInfo = true
                self.isLoading = false

            } else if chain == .cardano {

                let normalisedId = contractAddress.lowercased()
                let metadata: CardanoTokenMetadata
                do {
                    metadata = try await CardanoNativeTokensService.shared.resolveMetadata(assetId: normalisedId)
                } catch CardanoNativeTokensServiceError.assetNotFound {
                    self.error = TokenNotFoundError()
                    self.isLoading = false
                    return
                }
                // Prefer the built-in registry entry when we know the asset —
                // gives us the curated ticker, logo, and `priceProviderId`
                // (`USDM` instead of the `_USDM` masked from the CIP-67 prefix,
                // `usdm-2` instead of the empty default).
                let coinMeta = TokensStore.findTokenMeta(chain: chain, contractAddress: metadata.assetId)
                    ?? CoinMeta(
                        chain: chain,
                        ticker: metadata.ticker,
                        logo: metadata.registryLogo ?? .empty,
                        decimals: metadata.decimals,
                        priceProviderId: .empty,
                        contractAddress: metadata.assetId,
                        isNativeToken: false
                    )
                self.token = coinMeta
                self.tokenName = coinMeta.ticker
                self.tokenSymbol = coinMeta.ticker
                self.tokenDecimals = coinMeta.decimals
                self.showTokenInfo = true
                self.isLoading = false

            } else if ChainType.Solana == chain.chainType {

                let jupiterTokenInfos = try await SolanaService.shared.fetchTokensInfos(for: [contractAddress])

                if let jupiterTokenInfo = jupiterTokenInfos.first(where: {$0.contractAddress == contractAddress}) {

                    self.token = jupiterTokenInfo
                    self.tokenName = jupiterTokenInfo.ticker
                    self.tokenSymbol = jupiterTokenInfo.ticker
                    self.tokenDecimals = jupiterTokenInfo.decimals
                    self.showTokenInfo = true
                    self.isLoading = false

                } else {

                    self.error = TokenNotFoundError()
                    self.isLoading = false

                }

            } else {

                // EVM, TRON, and TON all share the same (name, symbol, decimals) lookup pattern
                let tokenInfo: (name: String, symbol: String, decimals: Int)

                switch chain.chainType {
                case .EVM:
                    let service = try EvmService.getService(forChain: chain)
                    tokenInfo = try await service.getTokenInfo(contractAddress: contractAddress)
                case .Tron:
                    tokenInfo = try await TronService.shared.getTokenInfo(contractAddress: contractAddress)
                case .Ton:
                    tokenInfo = try await TonService.shared.getTokenInfo(contractAddress: contractAddress)
                default:
                    self.error = TokenNotFoundError()
                    self.isLoading = false
                    return
                }

                let (name, symbol, decimals) = tokenInfo

                if !name.isEmpty, !symbol.isEmpty, decimals > 0 {
                    if vault.nativeCoin(for: chain) != nil {
                        self.token = CoinMeta(
                            chain: chain,
                            ticker: symbol,
                            logo: .empty,
                            decimals: decimals,
                            priceProviderId: .empty,
                            contractAddress: contractAddress,
                            isNativeToken: false
                        )
                        self.tokenName = name
                        self.tokenSymbol = symbol
                        self.tokenDecimals = decimals
                        self.showTokenInfo = true
                        self.isLoading = false
                    } else {
                        self.error = TokenNotFoundError()
                        self.isLoading = false
                    }

                } else {

                    self.error = TokenNotFoundError()
                    self.isLoading = false

                }

            }

        } catch let error as NSError {
            // Check for rate limit error
            if error.code == 429 {
                self.error = RateLimitError()
            } else {
                self.error = error
            }
            self.isLoading = false
        } catch {
            self.error = error
            self.isLoading = false
        }
    }

    /// Chain-aware placeholder for the search field. THORChain tokens are referenced by a
    /// `THOR.{SYMBOL}` bank-denom identifier rather than a contract address, so it gets a
    /// dedicated hint; every other chain keeps the generic search placeholder.
    private var searchPlaceholder: String {
        chain == .thorChain
            ? "findCustomTokenThorchainPlaceholder".localized
            : "search".localized
    }

    /// Validates whether the given input is a well-formed identifier for the current chain.
    /// For Cardano, the input is a native-token asset id (`policy_id.asset_name` hex).
    /// For THORChain, the input is a `THOR.{SYMBOL}` bank-denom identifier (THORChain
    /// tokens are bank denoms, not pool assets), so we validate that shape rather than a
    /// `thor1…` account address — the shared `AddressService.validateAddress` is reserved
    /// for real send/receive addresses and must keep rejecting token identifiers.
    /// Other chains validate the input as a contract/account address.
    /// Updates ``isValidAddress`` accordingly.
    /// - Parameter address: The raw input string.
    private func validateAddress(_ address: String) {
        if chain == .cardano {
            isValidAddress = (try? CardanoAssetId.parse(address)) != nil
        } else if chain == .thorChain {
            isValidAddress = ThorchainCustomTokenResolver.isValidInput(address)
        } else {
            isValidAddress = AddressService.validateAddress(address: address, chain: chain)
        }
    }

    /// Persists the resolved custom token to the vault and dismisses the screen.
    /// Shows an "adding token" loading indicator while the save is in progress.
    private func saveAssets() {
        if let customToken = self.token {
            isAddingToken = true
            Task {
                coinViewModel.handleSelection(isSelected: true, asset: customToken)
                await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
                try? await Task.sleep(for: .seconds(1)) // Small delay to improve UX
                isAddingToken = false
                dismiss()
            }
        }
    }

    private struct TokenNotFoundError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Token Not Found", comment: "Token not found error")
        }
    }

    private struct RateLimitError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("Too many requests. Please close this screen and try again later.", comment: "Rate limit error")
        }
    }

    private struct InvalidAddressError: LocalizedError {
        var errorDescription: String? {
            return NSLocalizedString("invalidAddress", comment: "Invalid address error")
        }
    }

}
