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
    private let thor = ThorchainService.shared
    private let maya = MayachainService.shared
    private let ton = TonService.shared
    private let tron = TronService.shared
    
    private let ripple = RippleService.shared
    private let cardano = CardanoService.shared
    private var localCache = ThreadSafeDictionary<String,BlockSpecificCacheItem>()
    
    /// Clear cache for a specific address to force fresh nonce fetch
    func clearCacheForAddress(_ address: String, chain: Chain) {
        localCache.clear()
    }
    
    /// Check if we should use cache for the given chain and cache key
    private func shouldUseCache(for chain: Chain, cacheKey: String) -> BlockChainSpecific? {
        // Skip cache for chains that support pending transactions to ensure fresh nonce
        guard !chain.supportsPendingTransactions else {
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
                                    feeMode: .fast,quote: quote)
        // Use centralized cache checking method
        if let cachedResult = shouldUseCache(for: tx.fromCoin.chain, cacheKey: cacheKey) {
            return cachedResult
        }
        
        let gasLimit = try await estimateSwapGasLimit(tx: tx)
        let specific = try await fetchSpecific(
            for: tx.fromCoin,
            action: .swap,
            sendMaxAmount: false,
            isDeposit: tx.isDeposit,
            transactionType: .unspecified,
            gasLimit: gasLimit,
            byteFee: nil,
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
    
    func fetchUTXOFee(coin: Coin, action: Action, feeMode: FeeMode) async throws -> BigInt {
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
            byteFee: tx.byteFee,
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
            byteFee: tx.gasLimit,
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
                       byteFee: BigInt?,
                       fromAddress: String?,
                       toAddress: String?,
                       memo: String?,
                       feeMode: FeeMode,
                       amount: BigInt?) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .zcash:
            return .UTXO(byteFee: coin.feeDefault.toBigInt(), sendMaxAmount: sendMaxAmount)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let  byteFeeValue = try await fetchUTXOFee(coin: coin, action: action, feeMode: feeMode)
            return .UTXO(byteFee: byteFeeValue, sendMaxAmount: sendMaxAmount)
        case .cardano:
            let ttl = try await cardano.calculateDynamicTTL()
            // For Cardano, we use fixed fee in BlockChainSpecific and calculate dynamic fee later
            // This follows the same pattern as UTXO chains where dynamic calculation happens in the ViewModel
            let estimatedFee = cardano.estimateTransactionFee()
            return .Cardano(byteFee: BigInt(estimatedFee), sendMaxAmount: sendMaxAmount, ttl: ttl)
        case .thorChain:
            _ = try await thor.getTHORChainChainID()
            let account = try await thor.fetchAccountNumber(coin.address)
            let fee = try await thor.fetchFeePrice()
            
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
            async let recentBlockHashPromise = sol.fetchRecentBlockhash()
            async let highPriorityFeePromise = sol.fetchHighPriorityFee(account: coin.address)
            
            let recentBlockHash = try await recentBlockHashPromise
            let highPriorityFee = try await highPriorityFeePromise
            
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
                
                // TODO: Add rent exemption balance check here
                // If finalToAddress is nil (account needs creation), verify sender has enough SOL:
                // - 0.00203928 SOL for token account creation
                // - Plus transaction fees
                // - Plus maintaining sender's own rent exemption
                
                return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: associatedTokenAddressFrom, toAddressPubKey: finalToAddress, hasProgramId: isToken2022)
            }
            
            return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)
            
        case .sui:
            let (referenceGasPrice, allCoins) = try await sui.getGasInfo(coin: coin)
            return .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins)
            
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
        
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain,.ethereumSepolia, .mantle:
            let gasLimit = gasLimit ?? normalizeGasLimit(coin: coin, action: action)
            let feeService = try EthereumFeeService(chain: coin.chain)
            let fee = try await feeService.calculateFees(chain: coin.chain,
                                                         limit: gasLimit,
                                                         isSwap: action == .swap,
                                                         fromAddress: coin.address,
                                                         feeMode: feeMode)
            switch fee {
            case .Eip1559(let newGasLimit, let maxFeePerGas, let maxPriorityFeePerGas, _,let nonce):
                return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: maxPriorityFeePerGas, nonce: nonce, gasLimit: newGasLimit)
            case .GasFee(let price, let newGasLimit, _,let nonce):
                return .Ethereum(maxFeePerGasWei: price, priorityFeeWei: BigInt.zero, nonce: nonce, gasLimit: newGasLimit)
            case .BasicFee(let amount,let nonce,let newGasLimit):
                return .Ethereum(maxFeePerGasWei: amount, priorityFeeWei: BigInt.zero, nonce: nonce, gasLimit: newGasLimit)
            }
            
        case .zksync:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            let (gasLimit, _, maxFeePerGas, maxPriorityFeePerGas, nonce) = try await service.getGasInfoZk(fromAddress: coin.address, toAddress: .zeroAddress)
            // Ensure priority fee does not exceed max fee
            let adjustedPriority = maxPriorityFeePerGas > maxFeePerGas ? maxFeePerGas : maxPriorityFeePerGas
            return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: adjustedPriority, nonce: nonce, gasLimit: gasLimit)
            
        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic, .dydx, .noble, .akash:
            let service = try CosmosServiceFactory.getService(forChain: coin.chain)
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
                    
                    let latestBlock = try await service.fetchLatestBlock(coin: coin)
                    
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
            
            //60 is bc of tss to wait till 5min so all devices can sign.
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
                return MantleService.defaultMantleSwapLimit
            }
            return BigInt(EVMHelper.defaultETHSwapGasUnit)
        }
    }
    
    func estimateERC20GasLimit(tx: SendTransaction) async  -> BigInt {
        do{
            let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
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
        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
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
        let service = try EvmServiceFactory.getService(forChain: tx.fromCoin.chain)
        switch(tx.quote){
        case .mayachain(_):
            return nil
        case .thorchain(_):
            return nil
        case .oneinch(let quote,_),.kyberswap(let quote, _),.lifi(let quote,_):
            if tx.fromCoin.isNativeToken {
                return try await service.estimateGasLimitForSwap(senderAddress: tx.fromCoin.address, toAddress: quote.tx.to, value: tx.amountInCoinDecimal, data: quote.tx.data)
            }
            return nil
        case .none:
            return nil
        }
        
    }
}
