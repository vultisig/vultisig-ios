//
//  CustomTokenViewModel.swift
//  VultisigApp
//

import Foundation

/// Owns the custom-token search form state and orchestrates per-chain token
/// resolution and address validation via ``CustomTokenResolver``. The screen binds
/// to this model and stays purely declarative.
@MainActor
final class CustomTokenViewModel: ObservableObject {
    private let vault: Vault
    private let chain: Chain
    private let resolver: CustomTokenResolver

    @Published var contractAddress: String = ""
    @Published var tokenSymbol: String = ""
    @Published var showTokenInfo: Bool = false
    @Published var isAddingToken: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published private(set) var isValidAddress: Bool = false
    @Published private(set) var token: CoinMeta?

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self.resolver = CustomTokenResolverFactory.make(chain: chain)
    }

    /// Chain-aware placeholder for the search field. THORChain tokens are referenced
    /// by a `THOR.{SYMBOL}` bank-denom identifier rather than a contract address, so
    /// it gets a dedicated hint; every other chain keeps the generic placeholder.
    var searchPlaceholder: String {
        chain == .thorChain
            ? "findCustomTokenThorchainPlaceholder".localized
            : "search".localized
    }

    /// Validates whether the given input is a well-formed identifier for the current
    /// chain and updates ``isValidAddress``.
    func validateAddress(_ address: String) {
        isValidAddress = resolver.validate(address)
    }

    /// Looks up token metadata for the current ``contractAddress`` via the chain's
    /// resolver. On success, populates the token preview; on failure, sets ``error``.
    func fetchTokenInfo() async {
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
            guard let coinMeta = try await resolver.fetchInfo(contract: contractAddress) else {
                self.error = TokenNotFoundError()
                self.isLoading = false
                return
            }

            // Vault-policy gate (EVM/Tron/TON): the vault must already hold the chain's
            // native coin. Read here — after the lookup returns, on the main actor —
            // to match the original read-after-network timing.
            if resolver.requiresVaultNativeCoin, vault.nativeCoin(for: chain) == nil {
                self.error = TokenNotFoundError()
                self.isLoading = false
                return
            }

            self.token = coinMeta
            self.tokenSymbol = coinMeta.ticker
            self.showTokenInfo = true
            self.isLoading = false

        } catch HTTPError.statusCode(429, _) {
            // HTTPClient-based lookups (Terra CW20) surface rate limiting as a typed
            // status-code error rather than an NSError with code 429.
            self.error = RateLimitError()
            self.isLoading = false
        } catch is CancellationError {
            // A cancelled lookup is not a failure the user needs to see; just stop the
            // spinner.
            self.isLoading = false
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

    /// Persists the resolved custom token to the vault.
    /// - Returns: `true` when a token was saved (so the caller can dismiss), `false`
    ///   when there was no resolved token to add.
    func saveAssets(coinSelectionViewModel: CoinSelectionViewModel) async -> Bool {
        guard let customToken = token else { return false }
        isAddingToken = true
        coinSelectionViewModel.handleSelection(isSelected: true, asset: customToken)
        await CoinService.saveAssets(for: vault, selection: coinSelectionViewModel.selection)
        isAddingToken = false
        return true
    }
}

// MARK: - Errors

struct TokenNotFoundError: LocalizedError {
    var errorDescription: String? {
        return NSLocalizedString("Token Not Found", comment: "Token not found error")
    }
}

struct RateLimitError: LocalizedError {
    var errorDescription: String? {
        return NSLocalizedString("Too many requests. Please close this screen and try again later.", comment: "Rate limit error")
    }
}

struct InvalidAddressError: LocalizedError {
    var errorDescription: String? {
        return NSLocalizedString("invalidAddress", comment: "Invalid address error")
    }
}
