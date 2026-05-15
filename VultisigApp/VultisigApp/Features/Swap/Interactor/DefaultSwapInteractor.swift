//
//  DefaultSwapInteractor.swift
//  VultisigApp
//
//  Concrete `SwapInteractor` wiring. Production builds via `.live` with the
//  existing `.shared` singletons; tests construct directly with mocks.
//

import BigInt
import Foundation

struct DefaultSwapInteractor: SwapInteractor {
    let quote: QuoteServiceProtocol
    let blockchain: BlockChainServiceProtocol
    let balance: BalanceServiceProtocol
    let fastVault: FastVaultServiceProtocol

    static var live: SwapInteractor {
        DefaultSwapInteractor(
            quote: SwapService.shared,
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared
        )
    }

    // swiftlint:disable:next async_without_await
    func loadFastVault(vault: Vault) async -> Bool {
        // Cached value populated by `FastVaultEligibilityRefresher` on app
        // foreground + vault switch. Sync read; no network call on the hot path.
        // The `async` is required by `SwapInteractor` protocol conformance.
        vault.fastVaultEligibility
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String
    ) async throws -> SwapQuoteResult? {
        guard !amount.isZero else { return nil }
        guard fromCoin != toCoin else {
            throw SwapCryptoLogic.Errors.sameAsset
        }

        let vultTier = await VultTierService().fetchDiscountTier(for: vault)
        let vultDiscountBps = vultTier?.bpsDiscount ?? 0
        let referralDiscountBps = referredCode.isEmpty
            ? 0
            : max(
                0,
                THORChainSwaps.affiliateFeeRateBp
                    - THORChainSwaps.referredAffiliateFeeRateBp
                    - (Int(THORChainSwaps.referredUserFeeRateBp) ?? 0)
            )

        let fetched = try await self.quote.fetchQuote(
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            isAffiliate: SwapCryptoLogic.isAffiliate,
            referredCode: referredCode,
            vultTierDiscount: vultDiscountBps
        )

        return SwapQuoteResult(
            quote: fetched,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        try await blockchain.fetchSwapBlockChainSpecific(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            quote: quote
        )
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        try await SwapCryptoLogic.thorchainFee(
            for: chainSpecific,
            fromCoin: fromCoin,
            fromAmount: fromAmount,
            vault: vault
        )
    }

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        let chainSpecific = try await fetchChainSpecific(
            fromCoin: transaction.fromCoin,
            toCoin: transaction.toCoin,
            fromAmount: transaction.fromAmount,
            quote: transaction.quote
        )
        return try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: chainSpecific,
            vault: vault
        )
    }

    func updateBalance(for coin: Coin) async {
        await balance.updateBalance(for: coin)
    }
}
