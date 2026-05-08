//
//  SwapPayloadBuilder.swift
//  VultisigApp
//
//  Pure-ish swap payload assembly over `SwapDraft`. Mechanical port of the
//  body of `SwapCryptoLogic.buildSwapKeysignPayload(tx:vault:)`, with the
//  chain-specific fetch hoisted out so the builder is testable in isolation.
//  The legacy `(tx:vault:)` entry point delegates here during the bridge
//  phase; deleted alongside `SwapTransaction` in §5.
//

import BigInt
import Foundation

extension SwapCryptoLogic {

    /// Compute the network fee for the swap given the chain-specific data already fetched.
    /// EVM derives from gas price × limit; Cosmos/THORChain/etc. read directly off chainSpecific;
    /// UTXO + Cardano build a draft transfer via `KeysignPayloadFactory` to plan the fee.
    static func thorchainFee(
        for chainSpecific: BlockChainSpecific,
        draft: SwapDraft,
        vault: Vault
    ) async throws -> BigInt {
        switch chainSpecific {
        case let .Ethereum(maxFeePerGas, priorityFee, _, gasLimit):
            return (maxFeePerGas + priorityFee) * gasLimit

        case .UTXO, .Cardano:
            let keysignFactory = KeysignPayloadFactory()
            do {
                let keysignPayload = try await keysignFactory.buildTransfer(
                    coin: draft.fromCoin,
                    toAddress: draft.fromCoin.address,
                    amount: amountInCoinDecimal(draft: draft),
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: nil,
                    vault: vault
                )

                let planFee: BigInt
                switch draft.fromCoin.chain {
                case .cardano:
                    planFee = try CardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
                default:
                    let utxo = UTXOChainsHelper(coin: draft.fromCoin.coinType)
                    let plan = try utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
                    planFee = BigInt(plan.fee)
                }

                if planFee <= 0 && fromAmountDecimal(draft: draft) > 0 {
                    throw Errors.insufficientFunds
                }
                return planFee
            } catch {
                if error is KeysignPayloadFactory.Errors {
                    throw error
                }
                throw Errors.insufficientFunds
            }

        case .Cosmos, .THORChain, .Polkadot, .MayaChain, .Solana, .Sui, .Ton, .Ripple, .Tron:
            return chainSpecific.gas
        }
    }

    static func buildApprovePayload(draft: SwapDraft) -> ERC20ApprovePayload? {
        guard isApproveRequired(draft: draft), let spender = router(draft: draft) else {
            return nil
        }
        // Approve exact amount — no buffer needed for KyberSwap precision.
        return ERC20ApprovePayload(amount: amountInCoinDecimal(draft: draft), spender: spender)
    }

    /// Build the THORChain/MayaChain swap payload from a draft + selected quote.
    /// `now` parameterised so tests can pin the 15-minute expiration deterministically;
    /// production passes the default `Date()`.
    static func buildThorchainSwapPayload(
        draft: SwapDraft,
        quote: ThorchainSwapQuote,
        provider: SwapProvider,
        now: Date = Date()
    ) -> THORChainSwapPayload {
        let vaultAddress = quote.inboundAddress ?? draft.fromCoin.address
        let expirationTime = now.addingTimeInterval(60 * 15) // 15 mins
        return THORChainSwapPayload(
            fromAddress: draft.fromCoin.address,
            fromCoin: draft.fromCoin,
            toCoin: draft.toCoin,
            vaultAddress: vaultAddress,
            routerAddress: quote.router,
            fromAmount: amountInCoinDecimal(draft: draft),
            toAmountDecimal: toAmountDecimal(draft: draft),
            toAmountLimit: "0",
            streamingInterval: String(provider.streamingInterval),
            streamingQuantity: "0",
            expirationTime: UInt64(expirationTime.timeIntervalSince1970),
            isAffiliate: isAffiliate(draft: draft)
        )
    }

    /// Assemble the final `KeysignPayload` for a swap given a populated draft and the
    /// chain-specific data already fetched. UTXO-source swaps still hit the network
    /// inside `KeysignPayloadFactory.buildTransfer` for UTXO selection; non-UTXO
    /// sources are deterministic given the inputs.
    static func buildSwapKeysignPayload(
        draft: SwapDraft,
        chainSpecific: BlockChainSpecific,
        vault: Vault,
        now: Date = Date()
    ) async throws -> KeysignPayload {
        guard let quote = draft.quote else {
            throw Errors.unexpectedError
        }

        let keysignFactory = KeysignPayloadFactory()

        switch quote {
        case let .mayachain(quote):
            let toAddress = draft.fromCoin.isNativeToken ? quote.inboundAddress : quote.router
            return try await keysignFactory.buildTransfer(
                coin: draft.fromCoin,
                toAddress: toAddress ?? draft.fromCoin.address,
                amount: amountInCoinDecimal(draft: draft),
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .mayachain(buildThorchainSwapPayload(
                    draft: draft,
                    quote: quote,
                    provider: .mayachain,
                    now: now
                )),
                approvePayload: buildApprovePayload(draft: draft),
                vault: vault
            )

        case let .thorchain(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? draft.fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: draft.fromCoin,
                toAddress: toAddress,
                amount: amountInCoinDecimal(draft: draft),
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchain(buildThorchainSwapPayload(
                    draft: draft,
                    quote: quote,
                    provider: .thorchain,
                    now: now
                )),
                approvePayload: buildApprovePayload(draft: draft),
                vault: vault
            )

        case let .thorchainChainnet(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? draft.fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: draft.fromCoin,
                toAddress: toAddress,
                amount: amountInCoinDecimal(draft: draft),
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchainChainnet(buildThorchainSwapPayload(
                    draft: draft,
                    quote: quote,
                    provider: .thorchainChainnet,
                    now: now
                )),
                approvePayload: buildApprovePayload(draft: draft),
                vault: vault
            )

        case let .thorchainStagenet(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? draft.fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: draft.fromCoin,
                toAddress: toAddress,
                amount: amountInCoinDecimal(draft: draft),
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchainStagenet(buildThorchainSwapPayload(
                    draft: draft,
                    quote: quote,
                    provider: .thorchainStagenet,
                    now: now
                )),
                approvePayload: buildApprovePayload(draft: draft),
                vault: vault
            )

        case let .oneinch(evmQuote, _), let .lifi(evmQuote, _, _), let .kyberswap(evmQuote, _):
            let payload = GenericSwapPayload(
                fromCoin: draft.fromCoin,
                toCoin: draft.toCoin,
                fromAmount: amountInCoinDecimal(draft: draft),
                toAmountDecimal: toAmountDecimal(draft: draft),
                quote: evmQuote,
                provider: quote.swapProviderId ?? .oneInch
            )
            return try await keysignFactory.buildTransfer(
                coin: draft.fromCoin,
                toAddress: evmQuote.tx.to,
                amount: amountInCoinDecimal(draft: draft),
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: .generic(payload),
                approvePayload: buildApprovePayload(draft: draft),
                vault: vault
            )
        }
    }
}
