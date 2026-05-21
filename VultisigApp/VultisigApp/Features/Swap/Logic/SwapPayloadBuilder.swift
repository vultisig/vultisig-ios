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

        case let .swapkit(swapResponse, _, _):
            let evmQuote = try buildEVMQuoteFromSwapKit(swapResponse: swapResponse)
            // Re-derive the approve payload from SwapKit's `approvalTx` (or
            // fall back to the standard ERC20 path against `targetAddress`).
            let resolvedApprovePayload = buildSwapKitApprovePayload(
                fromCoin: fromCoin,
                amount: amountInCoin,
                swapResponse: swapResponse,
                fallback: approvePayload
            )
            let payload = GenericSwapPayload(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountInCoin,
                toAmountDecimal: toDecimal,
                quote: evmQuote,
                provider: .swapkit
            )
            return try await keysignFactory.buildTransfer(
                coin: fromCoin,
                toAddress: swapResponse.targetAddress,
                amount: amountInCoin,
                memo: nil,
                chainSpecific: chainSpecific,
                swapPayload: .generic(payload),
                approvePayload: resolvedApprovePayload,
                vault: vault
            )
        }
    }

    /// Translates a SwapKit `/v3/swap` response into the existing `EVMQuote`
    /// shape so the keysign dispatcher can reuse the OneInch / Solana paths
    /// unchanged. EVM and Solana are typed in Phase 1; other `txType` values
    /// throw a descriptive error so callers can surface "not yet supported".
    static func buildEVMQuoteFromSwapKit(
        swapResponse: SwapKitSwapResponse
    ) throws -> EVMQuote {
        switch swapResponse.tx {
        case .evm(let tx):
            // SwapKit V3 fixtures observed `tx.value` as decimal wei (e.g.
            // "10000000000000000"), but the docs describe an Ethers V6 tx
            // object where `value` can be hex (`0x...`). Be defensive on
            // the wire: detect the prefix and parse accordingly. Adjacent
            // fields (`gas` / `gasPrice`) are documented as hex. Throwing
            // here rather than silently zeroing — a malformed value would
            // otherwise build a tx that sends 0 native and looks correct.
            let value = try Self.parseEvmAmount(tx.value)
            let gasPrice = BigInt(tx.gasPrice.stripHexPrefix(), radix: 16) ?? .zero
            let gas = Int64(tx.gas.stripHexPrefix(), radix: 16) ?? 0
            // Trust SwapKit's `tx.gas` for the gas limit; the EVM helper
            // bumps gasPrice against the chain-specific fee oracle in
            // OneInchSwaps.getPreSignedInputData.
            let normalizedGas = gas == 0 ? EVMHelper.defaultETHSwapGasUnit : gas
            return EVMQuote(
                dstAmount: rawAmountString(from: swapResponse.expectedBuyAmount),
                tx: EVMQuote.Transaction(
                    from: tx.from,
                    to: tx.to,
                    data: tx.data,
                    value: String(value),
                    gasPrice: String(gasPrice),
                    gas: normalizedGas
                )
            )

        case .solana(let base64):
            // SwapKit returns a base64-encoded Solana wire-format tx. The
            // existing SolanaSwaps signer base64-decodes from `tx.data` and
            // injects the recent blockhash — preserve that contract by
            // stashing the base64 into the `data` field of an EVMQuote-shaped
            // value that flows through `SwapPayload.generic` and gets routed
            // to SolanaSwaps by `KeysignMessageFactory`.
            return EVMQuote(
                dstAmount: rawAmountString(from: swapResponse.expectedBuyAmount),
                tx: EVMQuote.Transaction(
                    from: swapResponse.sourceAddress,
                    to: swapResponse.targetAddress,
                    data: base64,
                    value: "0",
                    gasPrice: "0",
                    gas: 0
                )
            )

        case .unsupported(let txType, _):
            throw SwapKitError.unsupportedTxType(txType)
        }
    }

    /// SwapKit's `approvalTx` carries the exact spender + amount the EVM
    /// approve call needs. When it's populated we honour it verbatim; when
    /// absent we fall back to the caller's pre-built approve payload (which
    /// defaults to ERC20 approve against `targetAddress`).
    static func buildSwapKitApprovePayload(
        fromCoin: Coin,
        amount: BigInt,
        swapResponse: SwapKitSwapResponse,
        fallback: ERC20ApprovePayload?
    ) -> ERC20ApprovePayload? {
        guard fromCoin.shouldApprove else { return nil }
        if let approvalTx = swapResponse.approvalTx {
            // The spender lives in `approvalAddress` (or is encoded in
            // `approvalTx.data` after the `0x095ea7b3` selector). We prefer
            // the meta field — confirmed by the spike to match the calldata
            // spender — and fall back to the `to` field of the approve tx
            // itself.
            let spender = swapResponse.meta.approvalAddress ?? approvalTx.to
            return ERC20ApprovePayload(amount: amount, spender: spender)
        }
        return fallback
    }

    /// Parses an EVM-style amount string that may arrive as decimal wei or as
    /// `0x`-prefixed hex. Throws `SwapKitError.malformedAmount` on any
    /// unparseable input — silent coercion to zero would build a tx that
    /// sends 0 native and look syntactically correct.
    static func parseEvmAmount(_ raw: String) throws -> BigInt {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            if let value = BigInt(raw.stripHexPrefix(), radix: 16) {
                return value
            }
        } else if let value = BigInt(raw) {
            return value
        }
        throw SwapKitError.malformedAmount(raw)
    }

    private static func rawAmountString(from expectedBuyAmount: String) -> String {
        // SwapKit returns human-units decimals; OneInch expects raw base
        // units in `dstAmount`. We don't have the destination decimals
        // wired through this helper, so we surface `expectedBuyAmount`
        // verbatim — the downstream ranking already special-cases SwapKit
        // (see SwapQuote+Ranking.expectedNetToAmount).
        return expectedBuyAmount.isEmpty ? "0" : expectedBuyAmount
    }
}
