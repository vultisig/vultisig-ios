//
//  DefaultSwapInteractor.swift
//  VultisigApp
//
//  Concrete `SwapInteractor` wiring. Production builds via `.live` with the
//  existing `.shared` singletons; tests construct directly with mocks.
//
//  VultTierService is constructed inline rather than injected because it has
//  no shared state and isn't on the test surface that motivates this protocol;
//  if VM tests later need to control discount-tier behaviour, lift it to a
//  protocol seam at that point.
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

    func loadFastVault(vault: Vault) async -> Bool {
        let exists = await fastVault.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().contains("server-")
        return exists && !isLocalBackup
    }

    func fetchQuote(draft: SwapDraft, vault: Vault, referredCode: String) async throws -> SwapQuoteResult? {
        guard !SwapCryptoLogic.fromAmountDecimal(draft: draft).isZero else { return nil }
        guard draft.fromCoin != draft.toCoin else {
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

        let fetched = try await quote.fetchQuote(
            amount: SwapCryptoLogic.fromAmountDecimal(draft: draft),
            fromCoin: draft.fromCoin,
            toCoin: draft.toCoin,
            isAffiliate: SwapCryptoLogic.isAffiliate(draft: draft),
            referredCode: referredCode,
            vultTierDiscount: vultDiscountBps
        )

        return SwapQuoteResult(
            quote: fetched,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    func fetchChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific {
        try await blockchain.fetchSwapBlockChainSpecific(draft: draft)
    }

    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        draft: SwapDraft,
        vault: Vault
    ) async throws -> BigInt {
        try await SwapCryptoLogic.thorchainFee(for: chainSpecific, draft: draft, vault: vault)
    }

    func buildSwapKeysignPayload(draft: SwapDraft, vault: Vault) async throws -> KeysignPayload {
        let chainSpecific = try await fetchChainSpecific(draft: draft)
        return try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: chainSpecific,
            vault: vault
        )
    }

    func updateBalance(for coin: Coin) async {
        await balance.updateBalance(for: coin)
    }
}
