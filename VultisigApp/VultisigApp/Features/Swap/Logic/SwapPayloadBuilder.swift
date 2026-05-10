//
//  SwapPayloadBuilder.swift
//  VultisigApp
//
//  Pure-ish swap payload assembly. Helpers take only the primitives they
//  need; both `SwapDetailsViewModel` (form state) and `SwapTransaction`
//  (immutable hand-off) feed their own fields in.
//

import BigInt
import Foundation

extension SwapCryptoLogic {

    /// Compute the network fee for the swap given the chain-specific data already fetched.
    /// EVM derives from gas price × limit; Cosmos/THORChain/etc. read directly off chainSpecific;
    /// UTXO + Cardano build a draft transfer via `KeysignPayloadFactory` to plan the fee.
    static func thorchainFee(
        for chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt {
        switch chainSpecific {
        case let .Ethereum(maxFeePerGas, priorityFee, _, gasLimit):
            return (maxFeePerGas + priorityFee) * gasLimit

        case .UTXO, .Cardano:
            let keysignFactory = KeysignPayloadFactory()
            let amountInCoin = fromCoin.raw(for: fromAmount)
            do {
                let keysignPayload = try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: fromCoin.address,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: nil,
                    vault: vault
                )

                let planFee: BigInt
                switch fromCoin.chain {
                case .cardano:
                    planFee = try CardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
                default:
                    let utxo = UTXOChainsHelper(coin: fromCoin.coinType)
                    let plan = try utxo.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
                    planFee = BigInt(plan.fee)
                }

                if planFee <= 0 && fromAmount > 0 {
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

    static func buildApprovePayload(
        fromCoin: Coin,
        amount: BigInt,
        quote: SwapQuote?
    ) -> ERC20ApprovePayload? {
        guard isApproveRequired(fromCoin: fromCoin, quote: quote),
              let spender = router(quote: quote)
        else {
            return nil
        }
        return ERC20ApprovePayload(amount: amount, spender: spender)
    }

    /// Build the THORChain/MayaChain swap payload from primitives + selected quote.
    /// `now` parameterised so tests can pin the 15-minute expiration deterministically.
    static func buildThorchainSwapPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        quote: ThorchainSwapQuote,
        provider: SwapProvider,
        now: Date = Date()
    ) -> THORChainSwapPayload {
        let vaultAddress = quote.inboundAddress ?? fromCoin.address
        let expirationTime = now.addingTimeInterval(60 * 15)
        return THORChainSwapPayload(
            fromAddress: fromCoin.address,
            fromCoin: fromCoin,
            toCoin: toCoin,
            vaultAddress: vaultAddress,
            routerAddress: quote.router,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            toAmountLimit: "0",
            streamingInterval: String(provider.streamingInterval),
            streamingQuantity: "0",
            expirationTime: UInt64(expirationTime.timeIntervalSince1970),
            isAffiliate: SwapCryptoLogic.isAffiliate
        )
    }

    /// Assemble the final `KeysignPayload` for a swap given a finalised
    /// `SwapTransaction` + the chain-specific data already fetched.
    static func buildSwapKeysignPayload(
        transaction: SwapTransaction,
        chainSpecific: BlockChainSpecific,
        vault: Vault,
        now: Date = Date()
    ) async throws -> KeysignPayload {
        let keysignFactory = KeysignPayloadFactory()
        let fromCoin = transaction.fromCoin
        let toCoin = transaction.toCoin
        let amountInCoin = transaction.amountInCoinDecimal
        let toDecimal = transaction.toAmountDecimal
        let approvePayload = buildApprovePayload(
            fromCoin: fromCoin,
            amount: amountInCoin,
            quote: transaction.quote
        )

        switch transaction.quote {
        case let .mayachain(quote):
            let toAddress = fromCoin.isNativeToken ? quote.inboundAddress : quote.router
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: toAddress ?? fromCoin.address,
                amount: amountInCoin,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .mayachain(buildThorchainSwapPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    quote: quote,
                    provider: .mayachain,
                    now: now
                )),
                approvePayload: approvePayload,
                vault: vault
            )

        case let .thorchain(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: toAddress,
                amount: amountInCoin,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchain(buildThorchainSwapPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    quote: quote,
                    provider: .thorchain,
                    now: now
                )),
                approvePayload: approvePayload,
                vault: vault
            )

        case let .thorchainChainnet(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: toAddress,
                amount: amountInCoin,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchainChainnet(buildThorchainSwapPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    quote: quote,
                    provider: .thorchainChainnet,
                    now: now
                )),
                approvePayload: approvePayload,
                vault: vault
            )

        case let .thorchainStagenet(quote):
            let toAddress = quote.router ?? quote.inboundAddress ?? fromCoin.address
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: toAddress,
                amount: amountInCoin,
                memo: quote.memo,
                chainSpecific: chainSpecific,
                swapPayload: .thorchainStagenet(buildThorchainSwapPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    quote: quote,
                    provider: .thorchainStagenet,
                    now: now
                )),
                approvePayload: approvePayload,
                vault: vault
            )

        case let .oneinch(evmQuote, _), let .lifi(evmQuote, _, _), let .kyberswap(evmQuote, _):
            let payload = GenericSwapPayload(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountInCoin,
                toAmountDecimal: toDecimal,
                quote: evmQuote,
                provider: transaction.quote.swapProviderId ?? .oneInch
            )
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: evmQuote.tx.to,
                amount: amountInCoin,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: .generic(payload),
                approvePayload: approvePayload,
                vault: vault
            )
        }
    }
}
