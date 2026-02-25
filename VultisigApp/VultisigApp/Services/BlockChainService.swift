//
//  BlockChainService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt
import VultisigCommonData
import WalletCore

struct BlockSpecificCacheItem {
    let blockSpecific: BlockChainSpecific
    let date: Date
}
final class BlockChainService {

    static func normalizeUTXOFee(_ value: BigInt) -> BigInt {
        return value * 2 + value / 2 // x2.5 fee
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

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }

    static let shared = BlockChainService()

    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let dot = PolkadotService.shared
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

        // Fetch fresh blockhash
        guard let freshBlockhash = try await sol.fetchRecentBlockhash() else {
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

    func fetchSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        switch tx.coin.chainType {
        case .EVM:
            return try await fetchSpecificForEVM(tx: tx)
        default:
            return try await fetchSpecificForNonEVM(tx: tx)
        }
    }

    func fetchSpecific(tx: SwapTransaction) async throws -> BlockChainSpecific {
        let quote = "\(String(describing: tx.quote?.hashValue))"
        let cacheKey =  getCacheKey(for: tx.fromCoin,
                                    action: .swap,
                                    sendMaxAmount: false,
                                    isDeposit: tx.isDeposit,
                                    transactionType: .unspecified,
                                    fromAddress: tx.fromCoin.address,
                                    toAddress: nil,  // Swaps don't have a specific toAddress in the same way
                                    memo: nil,  // Swaps don't have memos
                                    feeMode: .fast, quote: quote)
        // Use centralized cache checking method
        if let cachedResult = shouldUseCache(for: tx.fromCoin.chain, cacheKey: cacheKey) {
            return cachedResult
        }

        let gasLimit = try await estimateSwapGasLimit(tx: tx)

        let action: Action
        switch tx.quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            action = .transfer
        default:
            action = .swap
        }

        let specific = try await fetchSpecific(
            for: tx.fromCoin,
            action: action,
            sendMaxAmount: false,
            isDeposit: tx.isDeposit,
            transactionType: .unspecified,
            gasLimit: gasLimit,
            fromAddress: tx.fromCoin.address,
            toAddress: nil,  // Swaps don't have a specific toAddress in the same way
            memo: nil,  // Swaps don't have memos
            feeMode: .fast,
            amount: nil
        )
        // Use centralized cache setting method
        setCacheIfAllowed(for: tx.fromCoin.chain, cacheKey: cacheKey, blockSpecific: specific)
        return specific
    }

    func fetchUTXOFee(coin: Coin, feeMode: FeeMode) async throws -> BigInt {
        let sats = try await utxo.fetchSatsPrice(coin: coin)

        // DOGE has extremely high base fees from API, need to reduce significantly
        let result: BigInt
        if coin.chain == .dogecoin {
            // For DOGE, the API returns 500k sats/byte which is too high for WalletCore
            // Use a much lower value that WalletCore can work with: divide by 10
            result = sats / 10 // 500k / 10 = 50k sats/byte (still high but workable)
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
                       amount: BigInt?) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .zcash:
            return .UTXO(byteFee: coin.feeDefault.toBigInt(), sendMaxAmount: sendMaxAmount)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let  byteFeeValue = try await fetchUTXOFee(coin: coin, feeMode: feeMode)
            return .UTXO(byteFee: byteFeeValue, sendMaxAmount: sendMaxAmount)
        case .cardano:
            let ttl = try await cardano.calculateDynamicTTL()
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

                // Important: Only return nil for toAddressPubKey if we're certain the account doesn't exist
                // Empty string from RPC doesn't mean the account doesn't exist
                let finalToAddress = associatedTokenAddressTo?.isEmpty == true ? nil : associatedTokenAddressTo

                return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(SolanaHelper.priorityFeePrice), priorityLimit: SolanaHelper.priorityFeeLimit, fromAddressPubKey: associatedTokenAddressFrom, toAddressPubKey: finalToAddress, hasProgramId: isToken2022)
            }

            return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(SolanaHelper.priorityFeePrice), priorityLimit: SolanaHelper.priorityFeeLimit, fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)

        case .sui:
            let (referenceGasPrice, allCoins) = try await sui.getGasInfo(coin: coin)

            // Calculate dynamic gas budget using dry run simulation
            let gasBudget: BigInt
            if let amount = amount, amount > 0 {
                // Create a temporary keysign payload for simulation
                let tempPayload = KeysignPayload(
                    coin: coin,
                    toAddress: toAddress ?? coin.address, // Use same address for simulation if toAddress is nil
                    toAmount: amount,
                    chainSpecific: .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins, gasBudget: BigInt(3000000)), // Use default for initial payload
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
                    skipBroadcast: false,
                    signData: nil
                )

                do {
                    // Get zero-signed transaction for simulation
                    let txSerialized = try SuiHelper.getZeroSignedTransaction(keysignPayload: tempPayload)

                    // Simulate transaction to get accurate gas estimate
                    let (computationCost, storageCost) = try await sui.dryRunTransaction(transactionBytes: txSerialized)

                    // Calculate safe gas budget: (computation + storage) * 1.15 safety margin
                    let totalCost = computationCost + storageCost
                    gasBudget = (totalCost * 115) / 100

                    // Ensure minimum gas budget of 2000 (network requirement)
                    let finalGasBudget = max(gasBudget, BigInt(2000))

                    return .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins, gasBudget: finalGasBudget)
                } catch {
                    print("⚠️ Sui dry run failed, using default gas budget: \(error.localizedDescription)")
                    // Fall back to default + 15% safety margin
                    let defaultBudget = BigInt(3000000)
                    gasBudget = (defaultBudget * 115) / 100
                }
            } else {
                // No amount specified, use default with safety margin
                let defaultBudget = BigInt(3000000)
                gasBudget = (defaultBudget * 115) / 100
            }

            return .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins, gasBudget: gasBudget)

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

        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic, .dydx, .noble, .akash:
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

            // Chain-specific gas values
            let gas: UInt64
            switch coin.chain {
            case .terraClassic:
                gas = 100000000
            case .dydx:
                gas = 2500000000000000
            case .noble:
                gas = 20000
            case .akash:
                gas = 3000
            case .osmosis:
                gas = 25000 // Increased from 7500 to prevent "insufficient fee" errors
            default:
                gas = 7500
            }

            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: gas, transactionType: transactionType.rawValue, ibcDenomTrace: ibcDenomTrace)

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

            var senderJettonWallet: String = coin.contractAddress
            if !coin.isNativeToken {
                if let resolved = await TonService.shared.getJettonWalletAddressAsync(ownerAddress: coin.address, masterAddress: coin.contractAddress) {
                    senderJettonWallet = resolved
                }
            }
            return .Ton(sequenceNumber: seqno, expireAt: expireAt, bounceable: isBounceable, sendMaxAmount: sendMaxAmount, jettonAddress: senderJettonWallet, isActiveDestination: !isBounceable)
        case .ripple:

            let account = try await ripple.fetchAccountsInfo(for: coin.address)

            let sequence = account?.result?.accountData?.sequence ?? 0

            let lastLedgerSequence = account?.result?.ledgerCurrentIndex ?? 0

            // 60 is bc of tss to wait till 5min so all devices can sign.
            return .Ripple(sequence: UInt64(sequence), gas: 180000, lastLedgerSequence: UInt64(lastLedgerSequence) + 60)
        case .tron:
            return try await tron.getBlockInfo(coin: coin, to: toAddress, memo: memo)
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

    func estimateSwapGasLimit(tx: SwapTransaction) async throws -> BigInt? {
        if tx.fromCoin.chainType != .EVM {
            return nil
        }
        let service = try EvmService.getService(forChain: tx.fromCoin.chain)
        switch tx.quote {
        case .mayachain, .thorchain, .thorchainChainnet, .thorchainStagenet:
            // Swapping native ETH/AVAX/BSC to THORChain router is a contract call, not a simple transfer.
            // 23000 is too low. Using 120000 (same as ERC20) is safer.
            return BigInt(EVMHelper.defaultERC20TransferGasUnit)
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            if tx.fromCoin.isNativeToken {
                return try await service.estimateGasLimitForSwap(senderAddress: tx.fromCoin.address, toAddress: quote.tx.to, value: tx.amountInCoinDecimal, data: quote.tx.data)
            }
            return nil
        case .none:
            return nil
        }

    }
}
