//
//  CustomTokenViewModel.swift
//  VultisigApp
//

import Foundation

/// The single source of truth for what the custom-token search area is showing.
///
/// Success and failure are mutually exclusive by construction: entering any state
/// replaces the previous one, so a token that is *found* and then *fails* a follow-up
/// search can never linger alongside the error (and vice-versa).
enum CustomTokenSearchState: Equatable {
    /// Nothing to show — no search yet, or the field was cleared.
    case idle
    /// A lookup is in flight (drives the search spinner).
    case loading
    /// A token resolved; carries the metadata for the result row and add button.
    case found(CoinMeta)
    /// The lookup failed. `message` is the user-facing reason; `showsRetry` hides the
    /// retry action for rate-limit errors (which the user must wait out), matching the
    /// original `!(error is RateLimitError)` policy.
    case invalid(message: String, showsRetry: Bool)
}

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
    @Published var isAddingToken: Bool = false
    @Published private(set) var isValidAddress: Bool = false
    @Published private(set) var searchState: CustomTokenSearchState = .idle

    /// The in-flight lookup, if any. A new search cancels it first (cancel-and-restart)
    /// so the most recently *started* search — not whichever network call happens to
    /// finish last — is the one that decides ``searchState``.
    private var searchTask: Task<Void, Never>?

    init(vault: Vault, chain: Chain, resolver: CustomTokenResolver? = nil) {
        self.vault = vault
        self.chain = chain
        self.resolver = resolver ?? CustomTokenResolverFactory.make(chain: chain)
    }

    /// Chain-aware placeholder for the search field. THORChain tokens are referenced
    /// by a `THOR.{SYMBOL}` bank-denom identifier rather than a contract address, and
    /// XRPL issued currencies by a `currency.issuer` pair, so both get a dedicated
    /// hint; every other chain keeps the generic placeholder.
    var searchPlaceholder: String {
        switch chain {
        case .thorChain:
            return "findCustomTokenThorchainPlaceholder".localized
        case .ripple:
            return "findCustomTokenRipplePlaceholder".localized
        default:
            return "search".localized
        }
    }

    /// Validates whether the given input is a well-formed identifier for the current
    /// chain and updates ``isValidAddress``. Any edit also supersedes an in-flight
    /// lookup (its result was for the previous input) and resets the search area to
    /// ``CustomTokenSearchState/idle`` so a stale result or error never lingers past a
    /// change to what is being searched.
    func validateAddress(_ address: String) {
        isValidAddress = resolver.validate(address)
        searchTask?.cancel()
        searchTask = nil
        searchState = .idle
    }

    /// Starts a token lookup for the current ``contractAddress``, cancelling any
    /// in-flight one first (cancel-and-restart). Returns the lookup task so callers can
    /// await completion; the view discards it. The most recently started search always
    /// wins — a superseded lookup is cancelled and its late result discarded.
    @discardableResult
    func search() -> Task<Void, Never> {
        searchTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchTokenInfo()
        }
        searchTask = task
        return task
    }

    /// Looks up token metadata via the chain's resolver and drives ``searchState``. Each
    /// terminal transition (found / invalid) replaces the previous one, so success and
    /// failure are never shown at once. The result is committed only if this lookup was
    /// not superseded (cancelled) by a newer search or a field edit.
    private func fetchTokenInfo() async {
        // Bail before touching any state if this task was already superseded — task
        // scheduling is not FIFO, so a cancelled search can start after a newer one has
        // already published its result. There is no suspension point between here and
        // `searchState = .loading` below, so passing this check means every mutation up
        // to the network `await` runs atomically for the winning search.
        guard !Task.isCancelled else { return }
        guard !contractAddress.isEmpty else { return }

        // Validate address format before making API calls
        guard isValidAddress else {
            searchState = invalidState(for: InvalidAddressError())
            return
        }

        searchState = .loading

        let contract = contractAddress
        let terminalState: CustomTokenSearchState
        do {
            if let coinMeta = try await resolver.fetchInfo(contract: contract) {
                // Vault-policy gate (EVM/Tron/TON): the vault must already hold the
                // chain's native coin. Read here — after the lookup returns, on the main
                // actor — to match the original read-after-network timing.
                if resolver.requiresVaultNativeCoin, vault.nativeCoin(for: chain) == nil {
                    terminalState = invalidState(for: TokenNotFoundError())
                } else {
                    terminalState = .found(coinMeta)
                }
            } else {
                terminalState = invalidState(for: TokenNotFoundError())
            }
        } catch HTTPError.statusCode(429, _) {
            // HTTPClient-based lookups (Terra CW20) surface rate limiting as a typed
            // status-code error rather than an NSError with code 429.
            terminalState = invalidState(for: RateLimitError())
        } catch is CancellationError {
            // A cancelled lookup is not a failure the user needs to see.
            return
        } catch let error as NSError {
            // Check for rate limit error
            terminalState = error.code == 429
                ? invalidState(for: RateLimitError())
                : invalidState(for: error)
        } catch {
            terminalState = invalidState(for: error)
        }

        // A newer search or a field edit cancelled this lookup while it was in flight —
        // discard its result rather than overwrite the current state.
        guard !Task.isCancelled else { return }
        if case .found(let coinMeta) = terminalState {
            tokenSymbol = coinMeta.ticker
        }
        searchState = terminalState
    }

    /// Maps a lookup error to a ``CustomTokenSearchState/invalid(message:showsRetry:)``,
    /// hiding the retry action for rate-limit errors (which the user must wait out).
    private func invalidState(for error: Error) -> CustomTokenSearchState {
        .invalid(message: error.localizedDescription, showsRetry: !(error is RateLimitError))
    }

    /// Persists the resolved custom token to the vault.
    /// - Returns: `true` when a token was saved (so the caller can dismiss), `false`
    ///   when there was no resolved token to add.
    func saveAssets(coinSelectionViewModel: CoinSelectionViewModel) async -> Bool {
        guard case .found(let customToken) = searchState else { return false }
        isAddingToken = true
        coinSelectionViewModel.handleSelection(isSelected: true, asset: customToken)
        // The other exit from the same sheet, and it saves the same shared
        // selection — so it needs the same carry-through, or adding a custom
        // token silently drops a held DeFi position the sheet never rendered.
        let selection = TokenSelectionLogic.selectionPreservingDefiPositions(
            selection: coinSelectionViewModel.selection,
            vaultCoins: vault.coins
        )
        await CoinService.saveAssets(for: vault, selection: selection)
        isAddingToken = false
        return true
    }
}

// MARK: - Errors

struct TokenNotFoundError: LocalizedError {
    var errorDescription: String? {
        "customTokenNotFound".localized
    }
}

struct RateLimitError: LocalizedError {
    var errorDescription: String? {
        "customTokenRateLimit".localized
    }
}

struct InvalidAddressError: LocalizedError {
    var errorDescription: String? {
        "invalidAddress".localized
    }
}
