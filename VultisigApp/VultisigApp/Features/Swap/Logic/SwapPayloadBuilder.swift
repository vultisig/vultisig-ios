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
    ///
    /// The on-chain minimum-output floor is enforced by the `LIM` field inside
    /// the node-returned `quote.memo` (driven by the `tolerance_bps` we send on
    /// the quote request); that memo is what gets signed verbatim. The
    /// `toAmountLimit` / `streamingQuantity` fields here travel in the proto
    /// payload for cross-device display — we mirror the node's derivation so
    /// they stay consistent with the signed memo instead of reading `0`.
    static func buildThorchainSwapPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        quote: ThorchainSwapQuote,
        provider: SwapProvider,
        toleranceBps: Int = SwapService.defaultThorchainToleranceBps,
        now: Date = Date()
    ) -> THORChainSwapPayload {
        let vaultAddress = quote.inboundAddress ?? fromCoin.address
        let expirationTime = now.addingTimeInterval(60 * 15)
        let toAmountLimit = thorchainToAmountLimit(
            expectedAmountOut: quote.expectedAmountOut,
            toleranceBps: toleranceBps
        )
        let streamingQuantity = quote.maxStreamingQuantity.map(String.init) ?? "0"
        return THORChainSwapPayload(
            fromAddress: fromCoin.address,
            fromCoin: fromCoin,
            toCoin: toCoin,
            vaultAddress: vaultAddress,
            routerAddress: quote.router,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            toAmountLimit: toAmountLimit,
            streamingInterval: String(provider.streamingInterval),
            streamingQuantity: streamingQuantity,
            expirationTime: UInt64(expirationTime.timeIntervalSince1970),
            isAffiliate: SwapCryptoLogic.isAffiliate
        )
    }

    /// Minimum acceptable output, mirroring the node's `LIM` derivation:
    /// `floor(expectedAmountOut × (10_000 − toleranceBps) / 10_000)`.
    /// `expectedAmountOut` is the quote's raw integer output (THORChain 1e8
    /// units). Returns `"0"` when the input can't be parsed or tolerance is out
    /// of range — the node-side memo `LIM` remains the authoritative floor.
    static func thorchainToAmountLimit(expectedAmountOut: String, toleranceBps: Int) -> String {
        guard toleranceBps >= 0, toleranceBps < 10_000,
              let expected = BigInt(expectedAmountOut), expected > 0 else {
            return "0"
        }
        let limit = expected * BigInt(10_000 - toleranceBps) / BigInt(10_000)
        return String(limit)
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
            // Attribute the affiliate fee to its coin so peers holding only
            // the serialized payload (the co-signer has no live quote) don't
            // guess. `swapFeeCoin` is what the initiator's own fiat display
            // uses, so both devices agree by construction.
            var swapFeeChain: String?
            var swapFeeTokenId: String?
            var swapFeeDecimals: Int?
            if transaction.quote.evmSwapFeeBigInt != nil {
                let resolvedFeeCoin = swapFeeCoin(
                    quote: transaction.quote,
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    feeCoin: transaction.feeCoin
                )
                swapFeeChain = resolvedFeeCoin.chain.name
                swapFeeTokenId = resolvedFeeCoin.contractAddress.nilIfEmpty
                swapFeeDecimals = resolvedFeeCoin.decimals
            }
            let payload = GenericSwapPayload(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountInCoin,
                toAmountDecimal: toDecimal,
                quote: evmQuote,
                provider: transaction.quote.swapProviderId ?? .oneInch,
                swapFeeChain: swapFeeChain,
                swapFeeTokenId: swapFeeTokenId,
                swapFeeDecimals: swapFeeDecimals
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
            // Phase 2: dispatch on SwapKit's `meta.txType`. EVM and Solana
            // ride `SwapPayload.generic` (their wire shape matches
            // `OneInchSwapPayload` 1:1); PSBT (Bitcoin) rides the new
            // `SwapPayload.swapkit` variant that wraps the bytes for cross-
            // device transit. Future phases (TRON, TON, SUI, Cardano) add
            // their own `txType` branches here.
            switch swapResponse.tx {
            case .evm, .solana:
                let evmQuote = try buildEVMQuoteFromSwapKit(swapResponse: swapResponse)
                // Re-derive the approve payload from SwapKit's `approvalTx`
                // (or fall back to the standard ERC20 path against
                // `targetAddress`).
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

            case .psbt(let base64):
                let swapKitPayload = try buildSwapKitPSBTPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PSBT: base64,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .dogecoinPsbt(let base64):
                let swapKitPayload = try buildSwapKitLegacyPSBTPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PSBT: base64,
                    txType: "PSBT_DOGE",
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .bitcoinCashPsbt(let base64):
                let swapKitPayload = try buildSwapKitLegacyPSBTPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PSBT: base64,
                    txType: "PSBT_BCH",
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .dashPsbt(let base64):
                let swapKitPayload = try buildSwapKitLegacyPSBTPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PSBT: base64,
                    txType: "PSBT_DASH",
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .zcashPsbt(let base64):
                let swapKitPayload = try buildSwapKitLegacyPSBTPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PSBT: base64,
                    txType: "PSBT_ZEC",
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .ton(let transfers):
                // TON source: SwapKit returns `[{address, amount}]`. We
                // JSON-encode the canonical array (verbatim from the wire) into
                // `tx_payload` bytes so the cosigning peer can reconstruct the
                // same transfer set. Signing reuses the existing TON send path
                // — landed in the consolidated signing PR.
                let swapKitPayload = try buildSwapKitTonPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    transfers: transfers,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .cardano:
                // Cardano source: deposit-address-only flow. SwapKit returns
                // no transaction body for Cardano source — Vultisig builds a
                // plain ADA transfer to `targetAddress` for `sellAmount` via
                // the existing Cardano send path. `tx_payload` is empty bytes;
                // routing info lives entirely in `targetAddress` + `fromAmount`.
                let swapKitPayload = buildSwapKitCardanoPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .cardanoPrebuilt(let cbor):
                // Cardano source: SwapKit-built CBOR flow. The unsigned
                // transaction envelope is handed to us verbatim — UTXO
                // selection, change splitting, and fee computation are all
                // done server-side. The dispatcher routes
                // `txType=CARDANO_PREBUILT` to `SwapKitCardanoSigner`, which
                // signs item 0 (the body) of `tx_payload` directly. We don't
                // re-build a Cardano transfer locally — that would compute a
                // different tx_id and break NEAR Intents tracking.
                //
                // `buildTransfer` still runs `selectCardanoUTXOs` (Koios
                // fetch) so the resulting `KeysignPayload.utxos` field is
                // populated for cross-device transit. The pre-built signer
                // ignores those UTXOs at signing time — the bytes in
                // `txPayload` are authoritative — but populating them keeps
                // the proto field uniform with the deposit-only path.
                let swapKitPayload = buildSwapKitCardanoPrebuiltPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    cbor: cbor,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .sui(let base64):
                // Sui source: SwapKit returns a base64-encoded pre-built
                // programmable transaction block (PTB), ~5KB. Existing Pay /
                // PaySui flows won't accept a serialized PTB — the signing
                // path is greenfield and lands in the consolidated signing
                // PR. Scaffold here just stages the bytes on the keysign
                // payload so the cosigning peer receives the canonical PTB
                // intact.
                let swapKitPayload = try buildSwapKitSuiPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    base64PTB: base64,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .tron(let tronTx):
                // TRON source: SwapKit returns a TronWeb-shaped object. We
                // JSON-encode the canonical representation into `tx_payload`
                // bytes so the cosigning peer reconstructs the same object.
                // `raw_data_hex` is the canonical input to WalletCore Tron
                // signing — surfaced as a top-level field on the payload so
                // the signing PR can pull it without re-parsing the JSON.
                let swapKitPayload = try buildSwapKitTronPayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    tronTx: tronTx,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: swapResponse.targetAddress,
                    amount: amountInCoin,
                    memo: nil,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .rippleDepositOnly:
                // XRP source: deposit-only flow modelled on Cardano. SwapKit
                // returns no transaction body — Vultisig builds a plain XRP
                // Payment to `resolvedTargetAddress` for `sellAmount` via
                // the existing `RippleHelper`. If a `destinationTag` was
                // resolved (top-level / meta / suffix), stringify it into
                // `memo` — `RippleHelper.getPreSignedInputData` parses
                // numeric memos and attaches them as `destinationTag` on
                // the `RippleOperationPayment`.
                let resolvedTarget = swapResponse.resolvedTargetAddress
                let resolvedTag = swapResponse.resolvedDestinationTag
                let tagMemo = resolvedTag.map { String($0) }
                let swapKitPayload = buildSwapKitRipplePayload(
                    fromCoin: fromCoin,
                    toCoin: toCoin,
                    fromAmountInCoin: amountInCoin,
                    toAmountDecimal: toDecimal,
                    resolvedTargetAddress: resolvedTarget,
                    destinationTag: tagMemo,
                    swapResponse: swapResponse
                )
                return try await keysignFactory.buildTransfer(
                    coin: fromCoin,
                    toAddress: resolvedTarget,
                    amount: amountInCoin,
                    memo: tagMemo,
                    chainSpecific: chainSpecific,
                    swapPayload: .swapkit(swapKitPayload),
                    approvePayload: nil,
                    vault: vault
                )

            case .unsupported(let txType, _):
                throw SwapKitError.unsupportedTxType(txType)
            }
        }
    }

    /// Build a `SwapKitSwapPayload` for the BTC PSBT path: base64-decode the
    /// PSBT into raw bytes (peer doesn't need to round-trip through base64),
    /// stash the SwapKit-returned `targetAddress` + sub-provider tag, and
    /// keep `inboundAddress` + `memo` for forward compatibility with future
    /// providers that may populate them.
    static func buildSwapKitPSBTPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        base64PSBT: String,
        swapResponse: SwapKitSwapResponse
    ) throws -> SwapKitSwapPayload {
        guard let psbtBytes = Data(base64Encoded: base64PSBT) else {
            throw SwapKitError.generic(message: "SwapKit PSBT payload is not valid base64")
        }
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "PSBT",
            txPayload: psbtBytes,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the TON path. SwapKit returns
    /// `[{address, amount}]`; we JSON-encode that array verbatim into
    /// `tx_payload` so the cosigning peer reconstructs the same transfer set.
    /// Encoding uses `sortedKeys` for deterministic output across runs.
    static func buildSwapKitTonPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        transfers: [SwapKitTonTransfer],
        swapResponse: SwapKitSwapResponse
    ) throws -> SwapKitSwapPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadBytes: Data
        do {
            payloadBytes = try encoder.encode(transfers)
        } catch {
            throw SwapKitError.generic(message: "Failed to encode SwapKit TON payload: \(error)")
        }
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "TON",
            txPayload: payloadBytes,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the Cardano deposit-only path.
    /// SwapKit returns no transaction body (`tx: null` / omitted) — the
    /// cosigning peer rebuilds a plain ADA transfer to `targetAddress` for
    /// `fromAmount`. `tx_payload` is intentionally empty bytes.
    static func buildSwapKitCardanoPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        swapResponse: SwapKitSwapResponse
    ) -> SwapKitSwapPayload {
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "CARDANO",
            txPayload: Data(),
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the Cardano pre-built CBOR path.
    /// `cbor` is the unsigned transaction envelope returned by SwapKit —
    /// item 0 is the transaction body the keysign-side signer hashes with
    /// Blake2b-256. The bytes are passed verbatim so the cosigning peer
    /// derives the same digest. `txType` is `CARDANO_PREBUILT` (distinct
    /// from the deposit-only `CARDANO`) so the dispatcher can route
    /// independently.
    static func buildSwapKitCardanoPrebuiltPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        cbor: Data,
        swapResponse: SwapKitSwapResponse
    ) -> SwapKitSwapPayload {
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "CARDANO_PREBUILT",
            txPayload: cbor,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the Sui PTB path. SwapKit returns a
    /// base64-encoded pre-built programmable transaction block; we decode it
    /// into raw bytes for the keysign payload. The signing PR will hand these
    /// bytes to a greenfield Sui PTB signer.
    static func buildSwapKitSuiPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        base64PTB: String,
        swapResponse: SwapKitSwapResponse
    ) throws -> SwapKitSwapPayload {
        guard let ptbBytes = Data(base64Encoded: base64PTB) else {
            throw SwapKitError.generic(message: "SwapKit Sui payload is not valid base64")
        }
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "SUI",
            txPayload: ptbBytes,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the TRON path. SwapKit returns a
    /// TronWeb-shaped object; we JSON-encode the canonical representation
    /// (preserving the wire field names — `raw_data`, `raw_data_hex`, `txID`,
    /// `visible`) so the cosigning peer reconstructs it verbatim. `sortedKeys`
    /// keeps the byte output deterministic for fixture tests.
    static func buildSwapKitTronPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        tronTx: SwapKitTronTx,
        swapResponse: SwapKitSwapResponse
    ) throws -> SwapKitSwapPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadBytes: Data
        do {
            payloadBytes = try encoder.encode(tronTx)
        } catch {
            throw SwapKitError.generic(message: "Failed to encode SwapKit TRON payload: \(error)")
        }
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "TRON",
            txPayload: payloadBytes,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the legacy-P2PKH PSBT chains
    /// (DOGE / BCH / DASH / ZEC). Identical body to `buildSwapKitPSBTPayload`
    /// — base64-decode the PSBT bytes, stash SwapKit's deposit address +
    /// sub-provider tag — but the `txType` discriminator is per-chain so the
    /// keysign dispatcher routes to the right `SwapKit<Chain>Signer`. Wire
    /// shape on the cross-device proto matches the BTC variant 1:1; only the
    /// discriminator differs.
    static func buildSwapKitLegacyPSBTPayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        base64PSBT: String,
        txType: String,
        swapResponse: SwapKitSwapResponse
    ) throws -> SwapKitSwapPayload {
        guard let psbtBytes = Data(base64Encoded: base64PSBT) else {
            throw SwapKitError.generic(message: "SwapKit \(txType) payload is not valid base64")
        }
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: txType,
            txPayload: psbtBytes,
            targetAddress: swapResponse.targetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: nil,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
    }

    /// Build a `SwapKitSwapPayload` for the XRP deposit-only path. SwapKit
    /// returns no transaction body — the cosigning peer rebuilds a plain
    /// XRP Payment to `resolvedTargetAddress` for `fromAmount` and attaches
    /// the destination tag via the memo field (`RippleHelper` parses
    /// numeric memos into `destinationTag`). `tx_payload` is intentionally
    /// empty bytes; routing info lives in `targetAddress` + `memo`.
    static func buildSwapKitRipplePayload(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountInCoin: BigInt,
        toAmountDecimal: Decimal,
        resolvedTargetAddress: String,
        destinationTag: String?,
        swapResponse: SwapKitSwapResponse
    ) -> SwapKitSwapPayload {
        return SwapKitSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountInCoin,
            toAmountDecimal: toAmountDecimal,
            txType: "XRP",
            txPayload: Data(),
            targetAddress: resolvedTargetAddress,
            inboundAddress: swapResponse.inboundAddress,
            memo: destinationTag,
            subProvider: swapResponse.subProvider,
            swapID: swapResponse.swapId
        )
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

        case .psbt:
            // PSBT routes are dispatched at the outer call site via the new
            // `SwapPayload.swapkit` variant. Reaching this branch means a
            // caller mis-routed — preserve the typed error so the bug
            // surfaces in tests rather than silently building a broken EVM
            // quote.
            throw SwapKitError.unsupportedTxType("PSBT")

        case .ton:
            // TON routes flow through `SwapPayload.swapkit` at the outer call
            // site. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("TON")

        case .cardano:
            // Cardano deposit-only flow — no transaction body to mirror into
            // an EVMQuote. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("CARDANO")

        case .cardanoPrebuilt:
            // Cardano pre-built CBOR flow routes through `SwapPayload.swapkit`
            // at the outer call site. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("CARDANO_PREBUILT")

        case .sui:
            // Sui PTB routes flow through `SwapPayload.swapkit` at the outer
            // call site. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("SUI")

        case .tron:
            // TRON routes flow through `SwapPayload.swapkit` at the outer
            // call site. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("TRON")

        case .rippleDepositOnly:
            // XRP deposit-only flow — no transaction body to mirror into
            // an EVMQuote. Same defence-in-depth as PSBT.
            throw SwapKitError.unsupportedTxType("XRP")

        case .dogecoinPsbt:
            throw SwapKitError.unsupportedTxType("PSBT_DOGE")

        case .bitcoinCashPsbt:
            throw SwapKitError.unsupportedTxType("PSBT_BCH")

        case .dashPsbt:
            throw SwapKitError.unsupportedTxType("PSBT_DASH")

        case .zcashPsbt:
            throw SwapKitError.unsupportedTxType("PSBT_ZEC")

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
