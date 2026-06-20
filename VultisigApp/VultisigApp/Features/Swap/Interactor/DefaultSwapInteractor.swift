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
    let tierResolver: SwapDiscountTierResolving

    static var live: SwapInteractor {
        DefaultSwapInteractor(
            quote: SwapService.shared,
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared,
            tierResolver: VultTierService()
        )
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        guard !amount.isZero else { return nil }
        guard fromCoin != toCoin else {
            throw SwapCryptoLogic.Errors.sameAsset
        }

        // Read the per-session cached tier. The first call resolves it once
        // (VULT balance + Thorguard NFT eth_call) and caches it for the wallet;
        // every later quote reads the cached value, keeping the Thorguard
        // eth_call off the per-quote critical path. The screen warms this cache
        // on load, so by the time quotes run it's usually already populated.
        let vultTier = await tierResolver.resolveTierForSession(for: vault)
        let vultDiscountBps = vultTier?.bpsDiscount ?? 0
        let referralDiscountBps = referredCode.isEmpty
            ? 0
            : max(
                0,
                THORChainSwaps.affiliateFeeRateBp
                    - THORChainSwaps.referredAffiliateFeeRateBp
                    - (Int(THORChainSwaps.referredUserFeeRateBp) ?? 0)
            )

        let fetched = try await self.quote.fetchQuotes(
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            isAffiliate: SwapCryptoLogic.isAffiliate,
            referredCode: referredCode,
            vultTierDiscount: vultDiscountBps,
            slippageBps: slippageBps,
            recipientAddress: recipientAddress
        )

        return SwapQuoteResult(
            quote: fetched.best,
            allQuotes: fetched.ranked,
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
        // Safety net (HIGH tier): before building anything signable, verify the
        // finalised quote's on-chain output target actually equals the intended
        // external recipient. No-op when no external recipient is set. A mismatch
        // (provider dropped/misused the recipient param) throws and stops signing.
        try SwapRecipientVerifier.verify(transaction: transaction)

        let fetched = try await fetchChainSpecific(
            fromCoin: transaction.fromCoin,
            toCoin: transaction.toCoin,
            fromAmount: transaction.fromAmount,
            quote: transaction.quote
        )
        // Honour a user-supplied EVM gas limit from advanced settings. Applied to
        // the swap transaction only; the ERC-20 approval tx keeps its own
        // estimate (a swap's ~200k limit would massively over-fund the ~46k
        // approve). The override is a no-op on non-EVM chain-specific data.
        let chainSpecific: BlockChainSpecific
        if let gasLimit = transaction.advancedSettings.gasLimit {
            chainSpecific = fetched.overridingEVMGasLimit(BigInt(gasLimit))
        } else {
            chainSpecific = fetched
        }
        return try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: chainSpecific,
            vault: vault
        )
    }

    func updateBalance(for coin: Coin) async {
        await balance.updateBalance(for: coin)
    }

    func warmDiscountTier(for vault: Vault) async {
        _ = await tierResolver.resolveTierForSession(for: vault)
    }
}
