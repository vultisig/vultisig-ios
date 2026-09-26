import Foundation

/// Creates receipts from accepted broadcasts, without depending on the Done screen.
@MainActor
enum TransactionBroadcastReceipt {
    static func rows(hash: String, approveHash: String?, payload: KeysignPayload,
                     pubKey: String) -> [TransactionHistoryData] {
        guard isBroadcastHash(hash), TransactionActivityPolicy.isEligible(payload) else { return [] }
        let coin = payload.coin
        let swap = payload.swapPayload
        let tracking = trackingMetadata(hash: hash, payload: payload)
        let type: TransactionHistoryType
        if RippleTrustSetPresentation.isTrustSet(payload: payload) {
            type = .trustLineActivation
        } else if isLimitSwapMemo(payload.memo) {
            type = .limit
        } else if swap != nil {
            type = .swap
        } else {
            type = isTransfer(payload) ? .send : .transaction
        }
        let trust = type == .trustLineActivation ? RippleTrustSetPresentation.display(for: payload) : nil
        // Max-send inputs precede fee subtraction. Let the Done receipt enrich
        // the actual amount instead of publishing the pre-fee balance as sent.
        let hasAmount = type == .swap || type == .limit || (type == .send && !payload.chainSpecific.sendsMaxAmount)
        let row = TransactionHistoryData(
            id: UUID(), txHash: hash, approveTxHash: approveHash, pubKeyECDSA: pubKey,
            type: type, status: .inProgress, chainRawValue: coin.chain.rawValue,
            coinTicker: trust?.ticker ?? coin.ticker, coinLogo: coin.logo, coinChainLogo: coin.tokenChainLogo,
            amountCrypto: hasAmount ? (swap != nil ? payload.fromAmountString : payload.toAmountWithTickerString) : "",
            amountFiat: hasAmount ? (swap != nil ? payload.fromAmountFiatString : payload.toSendAmountFiatString) : "",
            fromAddress: coin.address, toAddress: trust?.issuer ?? swap?.toCoin.address ?? payload.toAddress,
            toCoinTicker: swap?.toCoin.ticker, toCoinLogo: swap?.toCoin.logo,
            toCoinChainLogo: swap?.toCoin.tokenChainLogo,
            toAmountCrypto: swap.map { "\($0.toAmountDecimal.formatForDisplay()) \($0.toCoin.ticker)" },
            toAmountFiat: swap == nil ? nil : payload.toSwapAmountFiatString,
            swapProvider: swap?.providerName ?? (type == .limit ? "THORChain" : nil),
            feeCrypto: "", feeFiat: "", network: coin.chain.name,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: coin.chain, txid: hash),
            createdAt: Date(), completedAt: nil, estimatedTime: ChainStatusConfig.config(for: coin.chain).estimatedTime,
            errorMessage: nil, swapTracking: tracking
        )
        var rows = [row]
        if let approveHash, approveHash != hash,
           let approval = approval(hash: approveHash, payload: payload, pubKey: pubKey) {
            rows.append(approval)
        }
        return rows
    }

    static func approval(hash: String, payload: KeysignPayload, pubKey: String) -> TransactionHistoryData? {
        guard isBroadcastHash(hash), !payload.skipBroadcast, let approval = payload.approvePayload else { return nil }
        return transaction(hash: hash, coin: payload.coin, pubKey: pubKey, type: .approve, toAddress: approval.spender)
    }

    /// Non-transfer receipts deliberately contain no amount or recipient claim.
    static func transaction(hash: String, coin: Coin, pubKey: String,
                            type: TransactionHistoryType = .transaction, toAddress: String = "") -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(), txHash: hash, approveTxHash: nil, pubKeyECDSA: pubKey,
            type: type, status: .inProgress, chainRawValue: coin.chain.rawValue,
            coinTicker: coin.ticker, coinLogo: coin.logo, coinChainLogo: coin.tokenChainLogo,
            amountCrypto: "", amountFiat: "", fromAddress: coin.address, toAddress: toAddress,
            toCoinTicker: nil, toCoinLogo: nil, toCoinChainLogo: nil, toAmountCrypto: nil, toAmountFiat: nil,
            swapProvider: nil, feeCrypto: "", feeFiat: "", network: coin.chain.name,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: coin.chain, txid: hash),
            createdAt: Date(), completedAt: nil, estimatedTime: ChainStatusConfig.config(for: coin.chain).estimatedTime,
            errorMessage: nil
        )
    }

    static func trackingMetadata(hash: String, payload: KeysignPayload) -> SwapTrackingMetadataData? {
        if isLimitSwapMemo(payload.memo) {
            return THORChainLimitTrackingService.metadata(broadcastHash: hash, sourceChain: payload.coin.chain)
        }
        guard let swap = payload.swapPayload else { return nil }
        switch swap {
        case .thorchain:
            return NativeSwapTrackingService.metadata(broadcastHash: hash, network: .thorChain)
        case .thorchainChainnet:
            return NativeSwapTrackingService.metadata(broadcastHash: hash, network: .thorChainChainnet)
        case .thorchainStagenet:
            return NativeSwapTrackingService.metadata(broadcastHash: hash, network: .thorChainStagenet)
        case .mayachain:
            return NativeSwapTrackingService.metadata(broadcastHash: hash, network: .mayaChain)
        case .swapkit:
            return swapKitMetadata(hash: hash, chain: payload.coin.chain)
        case .generic(let generic):
            if generic.provider == .swapkit { return swapKitMetadata(hash: hash, chain: payload.coin.chain) }
            let sameChain = generic.fromCoin.chain == generic.toCoin.chain
            let knownAtomicProvider: Bool
            switch generic.provider {
            case .oneInch, .kyberSwap, .jupiter, .lifi: knownAtomicProvider = true
            default: knownAtomicProvider = false
            }
            return SwapTrackingMetadataData(providerKind: TransactionActivityPolicy.nativeSourceProviderKind,
                broadcastHash: hash, subProvider: sameChain && knownAtomicProvider ? "atomic" : "sourceOnly")
        }
    }

    static func isBroadcastHash(_ hash: String) -> Bool {
        !hash.isEmpty && hash != SubstrateBroadcast.alreadyBroadcastedSentinel
    }

    private static func swapKitMetadata(hash: String, chain: Chain) -> SwapTrackingMetadataData? {
        guard let chainID = SwapKitChainIdentifier.chainId(for: chain) else { return nil }
        return SwapTrackingMetadataData(providerKind: SwapKitTrackingService.providerKind,
                                        broadcastHash: hash, sourceChainId: chainID)
    }

    private static func isTransfer(_ payload: KeysignPayload) -> Bool {
        guard !payload.isQbtcClaim, payload.qbtcClaimPayload == nil, payload.solanaStakingPayload == nil,
              payload.kaminoPayload == nil, payload.dappMetadata == nil, payload.signData == nil,
              payload.wasmExecuteContractPayload == nil, payload.tronTriggerSmartContractPayload == nil,
              !isModifyLimitSwapMemo(payload.memo) else { return false }
        let operation = SignedTransactionDecoder.decode(payload).operation
        if operation == .transfer { return true }
        guard operation == .unknown else { return false }
        // These send builders have no signed-content decoder yet. Explicit
        // staking/contract/dapp shapes were excluded above; a missing decoder
        // must not erase ordinary transfers from transaction history.
        switch payload.coin.chain {
        case .ripple, .sui, .polkadot, .bittensor, .cardano: return true
        default:
            if payload.coin.chainType == .UTXO { return true }
            if payload.coin.chainType == .EVM {
                return !(payload.memo ?? "").hasPrefix("0x")
            }
            return false
        }
    }
}
