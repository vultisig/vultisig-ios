//
//  YieldViewModel.swift
//  VultisigApp
//

import Foundation

/// Generic state container for a yield-vault dashboard, parameterized by a
/// `DefiYieldProvider`. Replaces the Circle-specific view model so Circle and
/// Noon render through one shell.
@MainActor
final class YieldViewModel: ObservableObject, Hashable, Equatable {
    nonisolated static func == (lhs: YieldViewModel, rhs: YieldViewModel) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private nonisolated let id = UUID()

    let providerID: DefiYieldProviderID
    let provider: DefiYieldProvider

    @Published var isLoading = false
    @Published var error: Error?
    @Published var missingEth = false
    @Published var hasCheckedAccount = false

    @Published var depositedBalance: Decimal = .zero
    @Published var nativeGasBalance: Decimal = .zero
    @Published var redemptions: [YieldRedemption] = []
    @Published var apy: Decimal?
    @Published var accountAddress: String?

    init(providerID: DefiYieldProviderID) {
        self.providerID = providerID
        self.provider = DefiYieldProviderFactory.make(providerID)
    }

    var presentation: YieldPresentation { provider.presentation }

    /// Providers without an account-setup step (Noon, direct EOA) are always
    /// "ready"; account-gated providers (Circle MSCA) require a resolved address.
    var hasAccount: Bool {
        !provider.requiresAccountSetup || (accountAddress?.isEmpty == false)
    }

    /// Provisions the provider's account (Circle MSCA). On success the resolved
    /// address flips `hasAccount`, swapping the setup card for the dashboard.
    func createAccount(vault: Vault) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let address = try await provider.createAccount(vault: vault)
            provider.persistAccountAddress(address, vault: vault)
            accountAddress = address
        } catch {
            self.error = error
        }
    }

    var claimableRedemption: YieldRedemption? {
        redemptions.first { $0.status == .claimable && $0.isClaimable }
    }

    var pendingRedemption: YieldRedemption? {
        redemptions.first { $0.status == .pending }
    }

    func seed(from position: YieldPosition?) {
        guard let position else { return }
        depositedBalance = position.depositedBalance
        nativeGasBalance = position.nativeGasBalance
        redemptions = position.redemptions.map { record in
            YieldRedemption(
                id: record.id,
                amount: record.amount,
                requestedAt: record.requestedAt,
                claimableAt: record.claimableAt,
                status: record.status
            )
        }
    }

    func refresh(vault: Vault) async {
        do {
            let position = try await provider.refreshPosition(vault: vault)
            depositedBalance = position.depositedBalance
            nativeGasBalance = position.nativeGasBalance
            redemptions = position.redemptions
        } catch {
            self.error = error
        }
    }

    func loadApy(vault: Vault) async {
        apy = try? await provider.apy(vault: vault)
    }
}
