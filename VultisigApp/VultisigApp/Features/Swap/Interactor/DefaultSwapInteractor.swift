//
//  DefaultSwapInteractor.swift
//  VultisigApp
//
//  Concrete `SwapInteractor` wiring. Production builds via `.live` with the
//  existing `.shared` singletons; tests construct directly with mocks.
//

import BigInt
import Foundation
import OSLog

struct DefaultSwapInteractor: SwapInteractor {
    let quote: QuoteServiceProtocol
    let blockchain: BlockChainServiceProtocol
    let balance: BalanceServiceProtocol
    let fastVault: FastVaultServiceProtocol
    let tierResolver: SwapDiscountTierResolving
    /// Inbound clients for the sign-time native-route halt re-check. Injected so
    /// the gate is unit-testable; production uses the shared singletons.
    var thorchainService: ThorchainService = .shared
    var mayachainService: MayachainService = .shared

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

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {
        let inboundFetch: () async throws -> [InboundAddress]

        if transaction.isLimit {
            // Limit orders carry no market quote but always route through
            // THORChain mainnet — apply the same fail-closed, cache-bypassing
            // re-check as a `.thorchain` market quote. (`LimitSwapPayloadAssembler`
            // additionally refuses halted/paused inbounds when it selects the
            // vault, but that read can be cache-served; this is the live gate.)
            inboundFetch = { [thorchainService] in
                try await thorchainService.fetchThorchainInboundAddressOrThrow(bypassCache: true)
            }
        } else {
            guard let quote = transaction.quote, quote.isNativeProtocolRoute else { return }
            switch quote {
            case .mayachain:
                inboundFetch = { [mayachainService] in
                    try await mayachainService.fetchInboundAddressOrThrow(bypassCache: true)
                }
            case .thorchain:
                inboundFetch = { [thorchainService] in
                    try await thorchainService.fetchThorchainInboundAddressOrThrow(bypassCache: true)
                }
            case .thorchainChainnet:
                // Read inbound from the matching node, not mainnet, so the
                // halt status reflects the network the quote actually routes on.
                inboundFetch = {
                    try await ThorchainChainnetService.shared.fetchThorchainInboundAddressOrThrow(bypassCache: true)
                }
            case .thorchainStagenet:
                inboundFetch = {
                    try await ThorchainStagenetService.shared.fetchThorchainInboundAddressOrThrow(bypassCache: true)
                }
            case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
                return
            }
        }

        let sourceChain = transaction.fromCoin.chain
        do {
            let inbound = try await inboundFetch()
            if SwapHaltGate.isHalted(chain: sourceChain, in: inbound) {
                throw SwapError.tradingHalted
            }
        } catch let error as SwapError {
            throw error
        } catch {
            // Fail closed: an unverifiable inbound re-check must not let a native
            // deposit proceed. Surface the retryable halt message so the user can
            // retry once the fetch recovers.
            let logger = Logger(subsystem: "com.vultisig.app", category: "swap-interactor")
            logger.warning("Sign-time halt re-check failed, blocking native route: \(error.localizedDescription, privacy: .public)")
            throw SwapError.tradingHalted
        }
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

    func refreshBalanceOrThrow(for coin: Coin) async throws {
        try await balance.refreshSpendableBalanceOrThrow(for: coin)
    }

    func warmDiscountTier(for vault: Vault) async {
        _ = await tierResolver.resolveTierForSession(for: vault)
    }
}
