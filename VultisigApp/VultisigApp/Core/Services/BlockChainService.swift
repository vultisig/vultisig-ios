//
//  BlockChainService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt
import OSLog
import VultisigCommonData
import WalletCore

struct BlockSpecificCacheItem {
    let blockSpecific: BlockChainSpecific
    let date: Date
}
final class BlockChainService {

    private let logger = Logger(subsystem: "com.vultisig.app", category: "blockchain-service")

    static func normalizeUTXOFee(_ value: BigInt) -> BigInt {
        return value * 2 + value / 2 // x2.5 fee
    }

    /// Dogecoin's `suggested_transaction_fee_per_byte_sat` from Blockchair is
    /// reported at the chain's relay-floor scale (~500k sats/byte), an order of
    /// magnitude above the rate other UTXO chains report. Android scales it by
    /// 0.25 (`gas * 5 / 20`) to land on a sane next-block rate; this base
    /// multiplier reproduces that intent and the fee mode tier is applied on
    /// top, so Low/Normal/Fast actually differ. At a live 500k sats/byte:
    /// Low ≈ 93,750, Normal = 125,000 (== Android), Fast = 312,500 sats/byte.
    static let dogeBaseFeeMultiplier: Float = 0.25

    static func dogeByteFee(suggestedSatsPerByte sats: BigInt, feeMode: FeeMode) -> BigInt {
        let prioritized = Float(sats) * dogeBaseFeeMultiplier * feeMode.utxoMultiplier
        return BigInt(prioritized)
    }

    static func normalizeEVMFee(_ value: BigInt) -> BigInt {
        let normalized = value + value / 2 // x1.5 fee
        return max(normalized, 1) // To avoid 0 miner tips
    }

    enum Action {
        case transfer
        case swap
    }

    enum Errors: String, Error, LocalizedError {
        case failToGetAccountNumber
        case failToGetSequenceNo
        case failToGetRecentBlockHash
        case failToGetAssociatedTokenAddressFrom
        case failToResolveJettonWallet

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }

    static let shared = BlockChainService()

    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let dot = PolkadotService.shared
    private let tao = BittensorService.shared
    private let maya = MayachainService.shared
    private let ton = TonService.shared
    private let tron = TronService.shared

    private let ripple = RippleService.shared
    private let cardano = CardanoService.shared
    private var localCache = ThreadSafeDictionary<String, BlockSpecificCacheItem>()

    func clearCacheForAddress() {
        localCache.clear()
    }

    /// Refresh Solana blockhash in the chainSpecific field of a KeysignPayload
    /// This should be called right before TSS signing to ensure the blockhash is fresh
    func refreshSolanaBlockhash(for payload: KeysignPayload) async throws -> KeysignPayload {
        guard payload.coin.chain == .solana else {
            // Not a Solana transaction, return as-is
            return payload
        }

        guard case .Solana(_, let priorityFee, let priorityLimit, let fromAddressPubKey, let toAddressPubKey, let hasProgramId) = payload.chainSpecific else {
            // Not a Solana chainSpecific, return as-is
            return payload
        }

        // Fetch a fresh FINALIZED blockhash. A `confirmed` blockhash can be
        // unknown to the load-balanced proxy's broadcast node (preflight
        // `BlockhashNotFound` even seconds after fetching it); a finalized,
        // rooted blockhash is known to every node. This refresh runs right
        // before the ceremony, so the ~13s finalized lag still leaves ample
        // validity.
        guard let freshBlockhash = try await sol.fetchFinalizedBlockhash() else {
            throw Errors.failToGetRecentBlockHash
        }

        // Create updated chainSpecific with fresh blockhash
        let updatedChainSpecific = BlockChainSpecific.Solana(
            recentBlockHash: freshBlockhash,
            priorityFee: priorityFee,
            priorityLimit: priorityLimit,
            fromAddressPubKey: fromAddressPubKey,
            toAddressPubKey: toAddressPubKey,
            hasProgramId: hasProgramId
        )

        // Solana native staking: the relayed `signData = .signSolana` bytes
        // (delegate / deactivate / withdraw / move) have the OLD blockhash baked
        // in, and a plain rebuild drops BOTH `signData` and the local-only
        // `solanaStakingPayload`. Without preserving them the keysign sees no
        // staking intent and signs a plain transfer to the validator vote
        // account. Preserve the staking payload across the chain-specific swap
        // and rebuild the unsigned staking tx with the fresh blockhash.
        if payload.solanaStakingPayload != nil {
            let staked = payload.withChainSpecific(updatedChainSpecific)
            let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: staked)
            return staked.withSignData(.signSolana(SignSolana(rawTransactions: [rawTransaction])))
        }

        // Create and return updated payload with fresh blockhash
        return KeysignPayload(
            coin: payload.coin,
            toAddress: payload.toAddress,
            toAmount: payload.toAmount,
            chainSpecific: updatedChainSpecific,
            utxos: payload.utxos,
            memo: payload.memo,
            swapPayload: payload.swapPayload,
            approvePayload: payload.approvePayload,
            vaultPubKeyECDSA: payload.vaultPubKeyECDSA,
            vaultLocalPartyID: payload.vaultLocalPartyID,
            libType: payload.libType,
            wasmExecuteContractPayload: payload.wasmExecuteContractPayload,
            tronTransferContractPayload: payload.tronTransferContractPayload,
            tronTriggerSmartContractPayload: payload.tronTriggerSmartContractPayload,
            tronTransferAssetContractPayload: payload.tronTransferAssetContractPayload,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: payload.skipBroadcast,
            signData: nil
        )
    }

    /// Check if we should use cache for the given chain and cache key
    private func shouldUseCache(for chain: Chain, cacheKey: String) -> BlockChainSpecific? {
        // Skip cache for chains that support pending transactions to ensure fresh nonce
        guard !chain.supportsPendingTransactions else {
            return nil
        }

        // Skip cache for Solana to ensure fresh blockhash (expires in ~60 seconds)
        guard chain != .solana else {
            return nil
        }

        guard let localCacheItem = localCache.get(cacheKey) else {
            return nil
        }

        let cacheSeconds = getCacheSeconds(chain: chain)
        guard localCacheItem.date.addingTimeInterval(cacheSeconds) > Date() else {
            return nil
        }

        return localCacheItem.blockSpecific
    }

    /// Set cache only for chains that don't support pending transactions
    private func setCacheIfAllowed(for chain: Chain, cacheKey: String, blockSpecific: BlockChainSpecific) {
        // Only cache for chains that don't support pending transactions
        guard !chain.supportsPendingTransactions else {
            return
        }

        // Don't cache Solana to ensure fresh blockhash
        guard chain != .solana else {
            return
        }

        localCache.set(cacheKey, BlockSpecificCacheItem(blockSpecific: blockSpecific, date: Date()))
    }

    private let TON_WALLET_STATE_UNINITIALIZED = "uninit"

    /// Unified entry point taking the new immutable `SendTransaction` struct.
    /// Dispatches to the cached chain-specific impls.
    func fetchSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        switch tx.coin.chainType {
        case .EVM:
            return try await fetchSpecificForEVM(tx: tx)
        default:
            return try await fetchSpecificForNonEVM(tx: tx)
        }
    }

    /// Primitive-typed entry point for the new SendInteractor. Wraps the
    /// private full-signature `fetchSpecific(for:action:…)` so the interactor
    /// doesn't need a `FunctionCallForm` reference (Phase A4 / Phase B).
    func fetchSendBlockChainSpecific(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        sendMaxAmount: Bool,
        isDeposit: Bool,
        transactionType: VSTransactionType,
        gasLimit: BigInt?,
        customGasLimit: BigInt?,
        feeMode: FeeMode,
        fromAddress: String
    ) async throws -> BlockChainSpecific {
        // EVM sends must size gas against the *real* recipient before the
        // keysign ceremony. Contract recipients, long memos, and chains with
        // higher intrinsic costs (Mantle, Base) all exceed the flat
        // 23000/120000 request default and would otherwise revert on-chain with
        // the keysign already spent. A user-set custom limit wins; non-EVM
        // chains pass through untouched.
        let resolvedGasLimit = await resolveEVMSendGasLimit(
            coin: coin,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            requestedGasLimit: gasLimit,
            customGasLimit: customGasLimit
        )

        return try await fetchSpecific(
            for: coin,
            action: .transfer,
            sendMaxAmount: sendMaxAmount,
            isDeposit: isDeposit,
            transactionType: transactionType,
            gasLimit: resolvedGasLimit,
            fromAddress: fromAddress,
            toAddress: toAddress,
            memo: memo,
            feeMode: feeMode,
            amount: amount
        )
    }

    func fetchSwapBlockChainSpecific(
        fromCoin: Coin,
        // swiftlint:disable:next unused_parameter
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific {
        let quoteHash = "\(String(describing: quote?.hashValue))"
        let isDeposit = SwapCryptoLogic.isDeposit(fromCoin: fromCoin)
        let cacheKey = getCacheKey(
            for: fromCoin,
            action: .swap,
            sendMaxAmount: false,
            isDeposit: isDeposit,
            transactionType: .unspecified,
            fromAddress: fromCoin.address,
            toAddress: nil,  // Swaps don't have a specific toAddress in the same way
            memo: nil,  // Swaps don't have memos
            feeMode: .fast, quote: quoteHash
        )
        if let cachedResult = shouldUseCache(for: fromCoin.chain, cacheKey: cacheKey) {
            return cachedResult
        }

        let gasLimit = try await estimateSwapGasLimit(
            fromCoin: fromCoin,
            fromAmount: fromAmount,
            quote: quote
        )

        let action: Action
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            action = .transfer
        default:
            action = .swap
        }

        let specific = try await fetchSpecific(
            for: fromCoin,
            action: action,
            sendMaxAmount: false,
            isDeposit: isDeposit,
            transactionType: .unspecified,
            gasLimit: gasLimit,
            fromAddress: fromCoin.address,
            toAddress: nil,  // Swaps don't have a specific toAddress in the same way
            memo: nil,  // Swaps don't have memos
            feeMode: .fast,
            amount: nil
        )
        setCacheIfAllowed(for: fromCoin.chain, cacheKey: cacheKey, blockSpecific: specific)
        return specific
    }

    func fetchUTXOFee(coin: Coin, feeMode: FeeMode) async throws -> BigInt {
        let sats = try await utxo.fetchSatsPrice(coin: coin)

        let result: BigInt
        if coin.chain == .dogecoin {
            // DOGE reports its rate at the relay-floor scale; rescale to a sane
            // next-block rate and apply the fee mode tier (see dogeByteFee).
            result = Self.dogeByteFee(suggestedSatsPerByte: sats, feeMode: feeMode)
        } else {
            // For other chains, use normal normalization and multipliers
            let normalized = Self.normalizeUTXOFee(sats)
            let prioritized = Float(normalized) * feeMode.utxoMultiplier
            result = BigInt(prioritized)
        }

        return result
    }

    func getCacheKey(for coin: Coin,
                     action: Action,
                     sendMaxAmount: Bool,
                     isDeposit: Bool,
                     transactionType: VSTransactionType,
                     fromAddress: String?,
                     toAddress: String?,
                     memo: String?,
                     feeMode: FeeMode,
                     quote: String?) -> String {
        let memoKey = memo?.isEmpty == false ? "memo-\(memo!.count)" : "none"
        return "\(coin.chain)-\(coin.ticker)-\(action)-\(sendMaxAmount)-\(isDeposit)-\(transactionType)-\(fromAddress ?? "")-\(toAddress ?? "")-\(memoKey)-\(feeMode) -\(quote ?? "")"
    }
}

extension BlockChainService {
    /// Resolve the gas limit for an EVM send.
    ///
    /// A user-set `customGasLimit` is honored exactly — the Send form lets the
    /// user override the limit and that choice must win over estimation. With no
    /// override, run `eth_estimateGas` against the *real* recipient (so contract
    /// receivers and long memos are sized correctly) and floor at the per-chain
    /// default. The estimate is used as-is, not inflated; if it isn't enough the
    /// user can raise the limit in the gas settings. Non-EVM chains pass
    /// `requestedGasLimit` through unchanged; if estimation fails the send still
    /// proceeds on the floor.
    ///
    /// Shared by the keysign-payload build (`fetchSendBlockChainSpecific`) and
    /// the Send form's fee display (`calculateEVMFee`) so both size gas the same
    /// way.
    func resolveEVMSendGasLimit(
        coin: Coin,
        fromAddress: String,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        requestedGasLimit: BigInt?,
        customGasLimit: BigInt?
    ) async -> BigInt? {
        if let customGasLimit {
            return customGasLimit
        }

        guard coin.chainType == .EVM else {
            return requestedGasLimit
        }

        let floor = max(normalizeGasLimit(coin: coin, action: .transfer), requestedGasLimit ?? .zero)

        // Without a recipient (e.g. early Send-form fee preview) there's nothing
        // to simulate against.
        guard !toAddress.isEmpty else {
            return floor
        }

        do {
            let service = try EvmService.getService(forChain: coin.chain)
            let estimated: BigInt
            if coin.isNativeToken {
                estimated = try await service.estimateGasForEthTransaction(
                    senderAddress: fromAddress,
                    recipientAddress: toAddress,
                    value: amount,
                    memo: memo
                )
            } else {
                estimated = try await service.estimateGasForERC20Transfer(
                    senderAddress: fromAddress,
                    contractAddress: coin.contractAddress,
                    recipientAddress: toAddress,
                    value: amount
                )
            }
            return max(estimated, floor)
        } catch {
            logger.warning("EVM send gas estimation failed for \(coin.chain.name, privacy: .public); using default gas limit")
            return floor
        }
    }
}

private extension BlockChainService {
    func getCacheSeconds(chain: Chain) -> TimeInterval {
        switch chain {
        case .solana:
            return 10
        default:
            return 60
        }
    }
    func fetchSpecificForNonEVM(tx: SendTransaction) async throws -> BlockChainSpecific {
        // Terra Classic's fee includes a proportional burn tax, so the cached
        // fee is only valid for the exact send amount. Key the cache on the
        // amount for that chain (reusing the free-form `quote` slot) so a
        // re-quote at a different amount doesn't serve a stale tax.
        let amountCacheComponent = tx.coin.chain == .terraClassic
            ? "amount-\(tx.amountInRaw.description)"
            : nil
        let cacheKey = getCacheKey(for: tx.coin,
                                   action: .transfer,
                                   sendMaxAmount: tx.sendMaxAmount,
                                   isDeposit: tx.isDeposit,
                                   transactionType: tx.transactionType,
                                   fromAddress: tx.fromAddress,
                                   toAddress: tx.toAddress,
                                   memo: tx.memo,
                                   feeMode: tx.feeMode,
                                   quote: amountCacheComponent)

        // Use centralized cache checking method
        if let cachedResult = shouldUseCache(for: tx.coin.chain, cacheKey: cacheKey) {
            return cachedResult
        }

        let blockSpecific = try await fetchSpecific(
            for: tx.coin,
            action: .transfer,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: tx.gasLimit,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            memo: tx.memo,
            feeMode: tx.feeMode,
            amount: tx.amountInRaw
        )
        // Use centralized cache setting method
        setCacheIfAllowed(for: tx.coin.chain, cacheKey: cacheKey, blockSpecific: blockSpecific)
        return blockSpecific
    }

    func fetchSpecificForEVM(tx: SendTransaction) async throws -> BlockChainSpecific {
        let cacheKey = getCacheKey(for: tx.coin,
                                   action: .transfer,
                                   sendMaxAmount: tx.sendMaxAmount,
                                   isDeposit: tx.isDeposit,
                                   transactionType: tx.transactionType,
                                   fromAddress: tx.fromAddress,
                                   toAddress: tx.toAddress,
                                   memo: tx.memo,
                                   feeMode: tx.feeMode,
                                   quote: nil)
        if let localCacheItem =  self.localCache.get(cacheKey) {
            // use the cache item
            if localCacheItem.date.addingTimeInterval(getCacheSeconds(chain: tx.coin.chain)) > Date() {
                return localCacheItem.blockSpecific
            }
        }

        let estimateGasLimit = tx.coin.isNativeToken ? try await estimateGasLimit(tx: tx):await estimateERC20GasLimit(tx: tx)
        let defaultGasLimit = BigInt(EVMHelper.defaultERC20TransferGasUnit)
        let gasLimit = max(defaultGasLimit, estimateGasLimit)

        let specific = try await fetchSpecific(
            for: tx.coin,
            action: .transfer,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: max(gasLimit, tx.gasLimit),
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            memo: tx.memo,
            feeMode: tx.feeMode,
            amount: tx.amountInRaw
        )
        self.localCache.set(cacheKey, BlockSpecificCacheItem(blockSpecific: specific, date: Date()))
        return specific
    }

    func fetchSpecific(for coin: Coin,
                       action: Action,
                       sendMaxAmount: Bool,
                       isDeposit: Bool,
                       transactionType: VSTransactionType,
                       gasLimit: BigInt?,
                       fromAddress: String?,
                       toAddress: String?,
                       memo: String?,
                       feeMode: FeeMode,
                       amount: BigInt?,
                       signData: SignData? = nil) async throws -> BlockChainSpecific {
        // dApp-supplied Sui PTBs (`signSui`) arrive already fully built: coins,
        // gas budget and reference gas price are baked into the BCS bytes that
        // the signing pipeline forwards verbatim. There are no construction
        // inputs to fetch, so return an empty SuiSpecific instead of hitting
        // the RPC (`getAllCoins` / reference-gas-price).
        if case .signSui = signData {
            return .Sui(referenceGasPrice: 0, coins: [], gasBudget: 0)
        }

        switch coin.chain {
        case .zcash:
            // Resolve the live ZIP-243 branch id at build time so it travels
            // with the payload to the signing helpers (covers native sends and
            // SwapKit ZEC swaps). nil when the RPC is down — signing then
            // refuses rather than producing a network-rejected tx.
            let zcashBranchId = await ZcashService.shared.getConsensusBranchIdHex()
            return .UTXO(byteFee: coin.feeDefault.toBigInt(), sendMaxAmount: sendMaxAmount, zcashBranchId: zcashBranchId)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let  byteFeeValue = try await fetchUTXOFee(coin: coin, feeMode: feeMode)
            return .UTXO(byteFee: byteFeeValue, sendMaxAmount: sendMaxAmount)
        case .cardano:
            let ttl = try await cardano.calculateDynamicTTL()
            // Placeholder fee only — UTXOs aren't selected yet here. The real
            // size-based `byteFee` is computed once by the initiator in
            // `KeysignPayloadFactory.buildTransfer` (via
            // `CardanoHelper.estimateDynamicByteFee`) and forced identically by
            // every co-signer for cross-platform MPC sighash parity.
            let estimatedFee = cardano.estimateTransactionFee()
            return .Cardano(byteFee: BigInt(estimatedFee), sendMaxAmount: sendMaxAmount, ttl: ttl)
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            let service = ThorchainServiceFactory.getService(for: coin.chain)
            _ = try await service.getTHORChainChainID()
            let account = try await service.fetchAccountNumber(coin.address)
            let fee = try await service.fetchFeePrice()

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .THORChain(accountNumber: accountNumber, sequence: sequence, fee: fee, isDeposit: isDeposit, transactionType: transactionType.rawValue)
        case .mayaChain:
            let account = try await maya.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .MayaChain(accountNumber: accountNumber, sequence: sequence, isDeposit: isDeposit)
        case .solana:
            let recentBlockHash = try await sol.fetchRecentBlockhash()

            guard let recentBlockHash else {
                throw Errors.failToGetRecentBlockHash
            }

            let defaultFee = BigInt(SolanaHelper.defaultPriorityFeePrice)
            let dynamicPriorityFee: BigInt
            do {
                let fee = try await sol.fetchRecentPrioritizationFees()
                dynamicPriorityFee = max(BigInt(fee), defaultFee)
            } catch {
                dynamicPriorityFee = defaultFee
            }

            if !coin.isNativeToken && fromAddress != nil {
                let (associatedTokenAddressFrom, senderIsToken2022) = try await sol.fetchTokenAssociatedAccountByOwner(for: fromAddress!, mintAddress: coin.contractAddress)

                // Validate that we got a valid sender account
                if associatedTokenAddressFrom.isEmpty {
                    throw Errors.failToGetAssociatedTokenAddressFrom
                }

                // Only fetch recipient's token account if toAddress is provided
                var associatedTokenAddressTo: String? = nil
                var isToken2022 = senderIsToken2022  // Use sender's program type as default

                if let toAddress, !toAddress.isEmpty {
                    let (toTokenAddress, recipientTokenProgram) = try await sol.fetchTokenAssociatedAccountByOwner(for: toAddress, mintAddress: coin.contractAddress)

                    associatedTokenAddressTo = toTokenAddress
                    // Only override if recipient has an account
                    if !toTokenAddress.isEmpty {
                        isToken2022 = recipientTokenProgram
                    } else {
                        // Fallback probe – derive deterministic ATAs and query getAccountInfo directly
                        if let walletCoreAddress = WalletCore.SolanaAddress(string: toAddress) {
                            let defaultAta = walletCoreAddress.defaultTokenAddress(tokenMintAddress: coin.contractAddress)
                            let token2022Ata = walletCoreAddress.token2022Address(tokenMintAddress: coin.contractAddress)

                            for ataAddress in [defaultAta, token2022Ata].compactMap({ $0 }) {
                                if ataAddress.isEmpty { continue }

                                // Check if account exists using getAccountInfo
                                let (exists, isToken2022Account) = try await sol.checkAccountExists(address: ataAddress)
                                if exists {
                                    associatedTokenAddressTo = ataAddress
                                    isToken2022 = isToken2022Account
                                    break
                                }
                            }
                        }
                    }
                }

                // If the RPC and the deterministic ATA probe both fail to find a recipient
                // token account, collapse the empty string to nil. The Solana signing helper
                // treats a nil `toAddressPubKey` as the signal to emit a
                // `createAssociatedTokenAccount` instruction alongside the SPL transfer so
                // the recipient's ATA is created in the same transaction (see
                // `SolanaHelper.getPreSignedInputData`). The extra ~0.00203 SOL rent for the
                // new account is surfaced via `BlockChainSpecific.gas` (see `SolanaHelper.ataRentLamports`).
                let finalToAddress = associatedTokenAddressTo?.isEmpty == true ? nil : associatedTokenAddressTo

                return .Solana(recentBlockHash: recentBlockHash, priorityFee: dynamicPriorityFee, priorityLimit: SolanaHelper.priorityFeeLimit, fromAddressPubKey: associatedTokenAddressFrom, toAddressPubKey: finalToAddress, hasProgramId: isToken2022)
            }

            return .Solana(recentBlockHash: recentBlockHash, priorityFee: dynamicPriorityFee, priorityLimit: SolanaHelper.priorityFeeLimit, fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)

        case .sui:
            let (referenceGasPrice, ownedCoins) = try await sui.getGasInfo(coin: coin)

            // Embed only the coin objects the send needs — not every owned
            // object. An unbounded set bloats the keysign payload (pairing QR /
            // TSS relay message) on wallets whose balance is scattered across
            // many objects, and the payload then fails to relay: the co-signer's
            // poll 404s and the initiator's transaction data expires before
            // signing starts. Selection is deterministic so every device signs
            // the identical transaction.
            let sendAmount = amount ?? .zero
            let defaultBudget = BigInt(3000000)

            func selectCoins(gasBudget: BigInt) -> [[String: String]] {
                SuiCoinType.selectPayloadCoins(
                    ownedCoins,
                    isNativeToken: coin.isNativeToken,
                    contractAddress: coin.contractAddress,
                    amount: sendAmount,
                    gasBudget: gasBudget
                )
            }

            // Calculate dynamic gas budget using dry run simulation
            let gasBudget: BigInt
            if let amount = amount, amount > 0 {
                // Simulate over a covering subset (default budget), so the dry-run
                // transaction is itself small enough to build on dusty wallets.
                let tempPayload = KeysignPayload(
                    coin: coin,
                    toAddress: toAddress ?? coin.address, // Use same address for simulation if toAddress is nil
                    toAmount: amount,
                    chainSpecific: .Sui(referenceGasPrice: referenceGasPrice, coins: selectCoins(gasBudget: defaultBudget), gasBudget: defaultBudget),
                    utxos: [],
                    memo: memo,
                    swapPayload: nil,
                    approvePayload: nil,
                    vaultPubKeyECDSA: "",
                    vaultLocalPartyID: "",
                    libType: "", // Not used for simulation
                    wasmExecuteContractPayload: nil,
                    tronTransferContractPayload: nil,
                    tronTriggerSmartContractPayload: nil,
                    tronTransferAssetContractPayload: nil,
                    qbtcClaimPayload: nil,
                    isQbtcClaim: false,
                    skipBroadcast: false,
                    signData: nil
                )

                do {
                    // Get zero-signed transaction for simulation
                    let txSerialized = try SuiHelper.getZeroSignedTransaction(keysignPayload: tempPayload)

                    // Simulate transaction to get accurate gas estimate
                    let (computationCost, storageCost) = try await sui.dryRunTransaction(transactionBytes: txSerialized)

                    // Calculate safe gas budget: (computation + storage) * 1.15 safety margin,
                    // and ensure the network minimum of 2000.
                    let totalCost = computationCost + storageCost
                    gasBudget = max((totalCost * 115) / 100, BigInt(2000))
                } catch {
                    print("⚠️ Sui dry run failed, using default gas budget: \(error.localizedDescription)")
                    // Fall back to default + 15% safety margin
                    gasBudget = (defaultBudget * 115) / 100
                }
            } else {
                // No amount specified, use default with safety margin
                gasBudget = (defaultBudget * 115) / 100
            }

            return .Sui(referenceGasPrice: referenceGasPrice, coins: selectCoins(gasBudget: gasBudget), gasBudget: gasBudget)

        case .polkadot:
            let gasInfo = try await dot.getGasInfo(fromAddress: coin.address)
            let dynamicFee = try await dot.calculateDynamicFee(
                fromAddress: coin.address,
                toAddress: toAddress ?? "",
                amount: amount ?? BigInt.zero,
                memo: memo
            )

            return .Polkadot(
                recentBlockHash: gasInfo.recentBlockHash,
                nonce: UInt64(gasInfo.nonce),
                currentBlockNumber: gasInfo.currentBlockNumber,
                specVersion: gasInfo.specVersion,
                transactionVersion: gasInfo.transactionVersion,
                genesisHash: gasInfo.genesisHash,
                gas: dynamicFee
            )

        case .bittensor:
            let gasInfo = try await tao.getGasInfo(fromAddress: coin.address)
            // Bittensor uses static fallback fee of 100_000 RAO (0.0001 TAO)
            let fee = BittensorHelper.defaultFee

            return .Polkadot(
                recentBlockHash: gasInfo.recentBlockHash,
                nonce: UInt64(gasInfo.nonce),
                currentBlockNumber: gasInfo.currentBlockNumber,
                specVersion: gasInfo.specVersion,
                transactionVersion: gasInfo.transactionVersion,
                genesisHash: gasInfo.genesisHash,
                gas: fee
            )

        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            let gasLimit = gasLimit ?? normalizeGasLimit(coin: coin, action: action)
            let feeService = try EthereumFeeService(chain: coin.chain)
            let fee = try await feeService.calculateFees(chain: coin.chain,
                                                         limit: gasLimit,
                                                         isSwap: action == .swap,
                                                         fromAddress: coin.address,
                                                         feeMode: feeMode)
            switch fee {
            case .Eip1559(let newGasLimit, let maxFeePerGas, let maxPriorityFeePerGas, _, let nonce):
                return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: maxPriorityFeePerGas, nonce: nonce, gasLimit: newGasLimit)
            case .GasFee(let price, let newGasLimit, _, let nonce):
                return .Ethereum(maxFeePerGasWei: price, priorityFeeWei: BigInt.zero, nonce: nonce, gasLimit: newGasLimit)
            case .BasicFee(let amount, let nonce, let newGasLimit):
                return .Ethereum(maxFeePerGasWei: amount, priorityFeeWei: BigInt.zero, nonce: nonce, gasLimit: newGasLimit)
            }

        case .zksync:
            let service = try EvmService.getService(forChain: coin.chain)
            let (gasLimit, _, maxFeePerGas, maxPriorityFeePerGas, nonce) = try await service.getGasInfoZk(fromAddress: coin.address, toAddress: .zeroAddress)
            // Ensure priority fee does not exceed max fee
            let adjustedPriority = maxPriorityFeePerGas > maxFeePerGas ? maxFeePerGas : maxPriorityFeePerGas
            return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: adjustedPriority, nonce: nonce, gasLimit: gasLimit)

        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic, .dydx, .noble, .akash, .qbtc:
            let service = try CosmosService.getService(forChain: coin.chain)
            let account = try await service.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }

            // Handle IBC denom traces for chains that support it
            var ibcDenomTrace: CosmosIbcDenomTraceDenomTrace? = nil

            // If this is an IBC transfer OR the coin has an IBC contract address, we need timeout info
            if transactionType == .ibcTransfer || coin.contractAddress.contains("ibc/") {
                switch coin.chain {
                case .gaiaChain, .kujira, .osmosis, .terra:
                    // Only fetch denom traces for actual IBC tokens
                    if coin.contractAddress.contains("ibc/") {
                        if let denomTrace = await service.fetchIbcDenomTraces(coin: coin) {
                            ibcDenomTrace = denomTrace
                        }
                    }

                    // Always set up timeout information for IBC transfers
                    let now = Date()
                    let tenMinutesFromNow = now.addingTimeInterval(10 * 60)
                    let timeoutInNanoseconds = UInt64(tenMinutesFromNow.timeIntervalSince1970 * 1_000_000_000)

                    let latestBlock = try await service.fetchLatestBlock()

                    // Update existing ibcDenomTrace or create a new one with timeout info
                    if ibcDenomTrace != nil {
                        ibcDenomTrace?.height = "\(latestBlock)_\(timeoutInNanoseconds)"
                    } else {
                        ibcDenomTrace = CosmosIbcDenomTraceDenomTrace(path: "", baseDenom: "", height: "\(latestBlock)_\(timeoutInNanoseconds)")
                    }
                default:
                    break
                }
            }

            // Optionally simulate to derive a dynamic per-tx gas limit the
            // initiator relays to co-signers (CosmosSpecific.gas_limit). Gated
            // OFF by default (see CosmosGasEstimationConfig): the relayed limit
            // is part of the SignDoc, so until every co-signer honors it the
            // SignDocs would diverge and the MPC signature would fail. nil when
            // the gate is off or simulation fails, in which case peers fall back
            // to the static per-chain gas limit.
            var dynamicGasLimit: UInt64?
            if CosmosGasEstimationConfig.shouldSimulate(chain: coin.chain),
               action == .transfer,
               coin.isNativeToken,
               let amount, amount > 0,
               let toAddress, !toAddress.isEmpty {
                dynamicGasLimit = await CosmosGasEstimator.estimateGasLimit(
                    chain: coin.chain,
                    hexPublicKey: coin.hexPublicKey,
                    fromAddress: coin.address,
                    toAddress: toAddress,
                    amount: String(amount),
                    memo: memo,
                    accountNumber: accountNumber,
                    sequence: sequence,
                    service: service
                )
            }

            // Chain-specific gas values
            var gas: UInt64
            switch coin.chain {
            case .terraClassic:
                // Base gas fee, denominated in the FEE denom the signer uses for
                // this send (see TerraHelperStruct.getPreSignedInputData). Only a
                // bank denom (USTC / uusd) pays its fee in its OWN denom, so it
                // gets the uusd base; native LUNC, CW20 (`terra1…`) and IBC
                // (`ibc/…`) all pay the fee in uluna and share the uluna base.
                // Both this gas number and the signed fee denom are gated on the
                // shared isBankDenom helper so they can't drift apart.
                //
                // Terra Classic prices its fee as `gasLimit × price`, and the
                // signer signs the relayed dynamic `gas_wanted`, so price the base
                // at that same effective limit (the relayed dynamic limit, else
                // the static 300k) up front. That keeps the stored `gas` — which
                // feeds both the Verify/keysign fee display and the signing input
                // — equal to the signed fee, instead of a stale fixed-limit value.
                gas = TerraClassicTax.baseGas(
                    contractAddress: coin.contractAddress,
                    isNativeToken: coin.isNativeToken,
                    gasLimit: dynamicGasLimit ?? TerraClassicTax.staticGasLimit
                )
            case .dydx:
                gas = 2500000000000000
            case .noble:
                gas = 20000
            default:
                gas = 7500
            }

            // Enforce the per-chain Cosmos fee floor at the effective gas limit:
            // the relayed dynamic limit when present, else the static per-chain
            // limit. Akash and Osmosis charge a non-zero minimum gas price; a
            // sub-floor fee is rejected on-chain with "insufficient fee" (this is
            // what replaces the old inline Akash 3000 / Osmosis 25000 literals).
            // Because chainSpecific.gas feeds both the displayed fee and the
            // WalletCore signing input, flooring here keeps the shown and signed
            // fee identical.
            // Resolve the gas limit that computes the on-chain minimum fee: the
            // relayed dynamic limit when present, else the static per-chain
            // limit. If the static lookup is unavailable, fall back to 0 so the
            // floor still runs — the absolute `minFeeFloor` keeps a floored chain
            // from silently skipping its floor, and `flooredFee` is a no-op for
            // unfloored chains.
            let staticGasLimit = (try? CosmosHelperConfig.getConfig(forChain: coin.chain).gasLimit) ?? 0
            let effectiveGasLimit = dynamicGasLimit ?? staticGasLimit
            gas = CosmosFeeFloorConfig.flooredFee(
                for: coin.chain,
                computedFee: gas,
                gasLimit: effectiveGasLimit
            )

            // Terra Classic charges a proportional burn tax (~0.5%) on the send
            // amount, paid in the SEND denom on top of the base gas fee. We fold
            // it into the single `gas` fee field, so it may only be added when the
            // fee is denominated in that same send denom: native LUNC (uluna fee,
            // uluna send) and the bank denom (USTC / uusd fee, uusd send). For
            // CW20 (`terra1…`) and IBC (`ibc/…`) the fee is paid in uluna while the
            // send is in the token's own denom, so folding token-unit tax here
            // would mix denoms (an 18-decimal token would inflate the uluna fee
            // wildly); those are excluded. The rate is fetched live (fails closed
            // to a conservative fallback).
            let taxPaidInSendDenom = coin.isNativeToken
                || TerraClassicTax.isBankDenom(contractAddress: coin.contractAddress, isNativeToken: coin.isNativeToken)
            if coin.chain == .terraClassic, action == .transfer, taxPaidInSendDenom, let amount, amount > 0 {
                let service = try CosmosService.getService(forChain: coin.chain)
                let rate = await service.fetchTerraClassicBurnTaxRate()
                let burnTax = TerraClassicTax.burnTax(amount: amount, rate: rate)
                if let burnTaxUInt = UInt64(burnTax.description) {
                    gas += burnTaxUInt
                }
            }

            return .Cosmos(
                accountNumber: accountNumber,
                sequence: sequence,
                gas: gas,
                transactionType: transactionType.rawValue,
                ibcDenomTrace: ibcDenomTrace,
                gasLimit: dynamicGasLimit
            )

        case .ton:
            let (seqno, expireAt) = try await ton.getSpecificTransactionInfo(coin)

            // Determine if address is bounceable
            var isBounceable = false
            if let toAddress = toAddress, !toAddress.isEmpty {
                // Check if destination wallet is uninitialized
                let walletState = try await ton.getWalletState(toAddress)
                let isUninitialized = walletState == TON_WALLET_STATE_UNINITIALIZED

                // If wallet is initialized and address starts with "E", it's bounceable
                if !isUninitialized && toAddress.starts(with: "E") {
                    isBounceable = true
                }
            }

            // For jettons we must send to the SENDER's jetton wallet, never the
            // master contract. A failed resolution must be a hard error — falling
            // back to the master address strands funds (tx succeeds, jettons stay put).
            var senderJettonWallet: String = coin.contractAddress
            if !coin.isNativeToken {
                guard let resolved = await ton.resolveJettonWalletAddress(ownerAddress: coin.address, masterAddress: coin.contractAddress) else {
                    throw Errors.failToResolveJettonWallet
                }
                senderJettonWallet = resolved
            }
            return .Ton(sequenceNumber: seqno, expireAt: expireAt, bounceable: isBounceable, sendMaxAmount: sendMaxAmount, jettonAddress: senderJettonWallet, isActiveDestination: !isBounceable)
        case .ripple:

            async let accountTask = ripple.fetchAccountsInfo(for: coin.address)
            async let feeTask = ripple.fetchFee()
            let (account, fee) = try await (accountTask, feeTask)

            let sequence = account?.result?.accountData?.sequence ?? 0

            let lastLedgerSequence = account?.result?.ledgerCurrentIndex ?? 0

            // 60 is bc of tss to wait till 5min so all devices can sign.
            return .Ripple(sequence: UInt64(sequence), gas: UInt64(fee), lastLedgerSequence: UInt64(lastLedgerSequence) + 60)
        case .tron:
            return try await tron.getBlockInfo(coin: coin, to: toAddress, memo: memo, isSwap: action == .swap)
        }
    }

    func normalizeGasLimit(coin: Coin, action: Action) -> BigInt {
        switch action {
        case .transfer:
            return BigInt(coin.feeDefault) ?? 0
        case .swap:
            // For Mantle, use the coin's default gas limit for swaps
            if coin.chain == .mantle {
                return EvmService.defaultMantleSwapLimit
            }
            return BigInt(EVMHelper.defaultETHSwapGasUnit)
        }
    }

    func estimateERC20GasLimit(tx: SendTransaction) async -> BigInt {
        do {
            let service = try EvmService.getService(forChain: tx.coin.chain)
            let gas = try await service.estimateGasForERC20Transfer(
                senderAddress: tx.coin.address,
                contractAddress: tx.coin.contractAddress,
                recipientAddress: .anyAddress,
                value: BigInt(stringLiteral: tx.coin.rawBalance)
            )
            return gas
        } catch {
            // failed to estimate ERC20 transfer gas limit
            return 0
        }
    }

    func estimateGasLimit(tx: SendTransaction) async throws -> BigInt {
        let service = try EvmService.getService(forChain: tx.coin.chain)
        let gas = try await service.estimateGasForEthTransaction(
            senderAddress: tx.coin.address,
            recipientAddress: .anyAddress,
            value: tx.amountInRaw,
            memo: tx.memo
        )
        return gas
    }

    func estimateSwapGasLimit(
        fromCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BigInt? {
        guard fromCoin.chainType == .EVM else { return nil }
        let service = try EvmService.getService(forChain: fromCoin.chain)
        switch quote {
        case .mayachain, .thorchain, .thorchainChainnet, .thorchainStagenet:
            // Swapping native ETH/AVAX/BSC to THORChain router is a contract call, not a simple transfer.
            // 23000 is too low. Using 120000 (same as ERC20) is safer.
            return BigInt(EVMHelper.defaultERC20TransferGasUnit)
        case .oneinch(let evmQuote, _), .kyberswap(let evmQuote, _), .lifi(let evmQuote, _, _):
            guard fromCoin.isNativeToken else { return nil }
            do {
                let amountInCoin = fromCoin.raw(for: fromAmount)
                return try await service.estimateGasLimitForSwap(
                    senderAddress: fromCoin.address,
                    toAddress: evmQuote.tx.to,
                    value: amountInCoin,
                    data: evmQuote.tx.data
                )
            } catch {
                return nil
            }
        case .swapkit(let response, _, _):
            guard fromCoin.isNativeToken, case let .evm(tx) = response.tx else { return nil }
            do {
                let amountInCoin = fromCoin.raw(for: fromAmount)
                return try await service.estimateGasLimitForSwap(
                    senderAddress: fromCoin.address,
                    toAddress: tx.to,
                    value: amountInCoin,
                    data: tx.data
                )
            } catch {
                return nil
            }
        case .jupiter:
            // Jupiter is Solana-only; the EVM-source guard above already returned
            // nil before reaching here. Kept for switch exhaustiveness.
            return nil
        case .none:
            return nil
        }

    }
}
