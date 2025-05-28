//
//  FeeService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt
import VultisigCommonData

struct BlockSpecificCacheItem {
    let blockSpecific: BlockChainSpecific
    let date: Date
}
final class BlockChainService {
    
    static func normalizeUTXOFee(_ value: BigInt) -> BigInt {
        return value * 2 + value / 2 // x2.5 fee
    }
    
    static func normalizeEVMFee(_ value: BigInt, chain: Chain? = nil) -> BigInt {
        print("🔌 BlockChainService: Normalizing EVM fee for chain: \(chain?.rawValue ?? "unknown")")
        print("🔌 BlockChainService: Original value: \(value)")
        
        var multiplier: BigInt = 3
        if chain == .base {
            multiplier = 5 // x2.5 fee for Base chain
            print("🔌 BlockChainService: Using higher multiplier (5/3 = 2.5x) for Base chain")
        }
        
        let normalized = value + (value / 2) * (multiplier / 3)
        print("🔌 BlockChainService: Normalized value: \(normalized)")
        
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
    private let atom = GaiaService.shared
    private let maya = MayachainService.shared
    private let kuji = KujiraService.shared
    private let dydx = DydxService.shared
    private let ton = TonService.shared
    private let osmo = OsmosisService.shared
    private let tron = TronService.shared
    
    private let ripple = RippleService.shared
    
    private let terra = TerraService.shared
    private let terraClassic = TerraClassicService.shared
    private let noble = NobleService.shared
    private let akash = AkashService.shared
    private var localCache = ThreadSafeDictionary<String,BlockSpecificCacheItem>()
    
    func fetchSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        switch tx.coin.chainType {
        case .EVM:
            return try await fetchSpecificForEVM(tx: tx)
        default:
            return try await fetchSpecificForNonEVM(tx: tx)
        }
    }
    @MainActor
    func fetchSpecific(tx: SwapTransaction) async throws -> BlockChainSpecific {
        print("🔍 SWAP: Fetching specific for swap transaction")
        print("🔍 SWAP: From coin: \(tx.fromCoin.ticker), chain: \(tx.fromCoin.chain.rawValue)")
        print("🔍 SWAP: To coin: \(tx.toCoin.ticker), chain: \(tx.toCoin.chain.rawValue)")
        print("🔍 SWAP: Is deposit: \(tx.isDeposit)")
        
        let cacheKey = getCacheKey(for: tx.fromCoin,
                                    action: .swap,
                                    sendMaxAmount: false,
                                    isDeposit: tx.isDeposit,
                                    transactionType: .unspecified,
                                    fromAddress: tx.fromCoin.address,
                                    feeMode: .fast)
        if let localCacheItem = self.localCache.get(cacheKey) {
            let cacheSeconds = getCacheSeconds(chain: tx.fromCoin.chain)
            // use the cache item
            if localCacheItem.date.addingTimeInterval(cacheSeconds) > Date() {
                print("🔍 SWAP: Using cached block specific: \(localCacheItem.blockSpecific)")
                return localCacheItem.blockSpecific
            }
        }
        
        let fromCoin = await tx.fromCoin
        let toCoin = await tx.toCoin
        
        print("🔍 SWAP: From: \(fromCoin.ticker) (\(fromCoin.chain.rawValue)) -> To: \(toCoin.ticker) (\(toCoin.chain.rawValue))")
        
        if (fromCoin.chain == .thorChain && toCoin.chain == .base) {
            print("🔍 SWAP: Special case - THOR to BASE swap detected")
            print("🔍 SWAP: Setting isDeposit to true for this direction")
            
            let specific = try await fetchSpecific(
                for: tx.fromCoin,
                action: .swap,
                sendMaxAmount: false,
                isDeposit: true, // All swap operations should use deposit flag
                transactionType: .unspecified,
                gasLimit: nil,
                byteFee: nil,
                fromAddress: nil,
                toAddress: nil,
                feeMode: .fast
            )
            print("🔍 SWAP: Generated specific for THOR->BASE: \(specific)")
            self.localCache.set(cacheKey, BlockSpecificCacheItem(blockSpecific: specific, date: Date()))
            return specific
        }
        
        print("🔍 SWAP: Standard swap case")
        print("🔍 SWAP: Using isDeposit value: \(tx.isDeposit)")
        
        let specific = try await fetchSpecific(
            for: tx.fromCoin,
            action: .swap,
            sendMaxAmount: false,
            isDeposit: tx.isDeposit,
            transactionType: .unspecified,
            gasLimit: nil,
            byteFee: nil,
            fromAddress: nil,
            toAddress: nil,
            feeMode: .fast
        )
        
        print("🔍 SWAP: Generated specific: \(specific)")
        self.localCache.set(cacheKey, BlockSpecificCacheItem(blockSpecific: specific, date: Date()))
        return specific
    }
    
    func fetchUTXOFee(coin: Coin, action: Action, feeMode: FeeMode) async throws -> BigInt {
        let sats = try await utxo.fetchSatsPrice(coin: coin)
        let normalized = Self.normalizeUTXOFee(sats)
        let prioritized = Float(normalized) * feeMode.utxoMultiplier
        return BigInt(prioritized)
    }
    
    func getCacheKey(for coin: Coin,
                     action: Action,
                     sendMaxAmount: Bool,
                     isDeposit: Bool,
                     transactionType: VSTransactionType,
                     fromAddress: String?,
                     feeMode: FeeMode) -> String {
        return "\(coin.chain)-\(action)-\(sendMaxAmount)-\(isDeposit)-\(transactionType)-\(fromAddress ?? "")-\(feeMode)"
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
                                   feeMode: tx.feeMode)
        if let localCacheItem =  self.localCache.get(cacheKey) {
            // use the cache item
            if localCacheItem.date.addingTimeInterval(getCacheSeconds(chain: tx.coin.chain)) > Date() {
                return localCacheItem.blockSpecific
            }
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
            feeMode: tx.feeMode
        )
        self.localCache.set(cacheKey, BlockSpecificCacheItem(blockSpecific: blockSpecific, date: Date()))
        return blockSpecific
    }
    
    func fetchSpecificForEVM(tx: SendTransaction) async throws -> BlockChainSpecific {
        let cacheKey = getCacheKey(for: tx.coin,
                                   action: .transfer,
                                   sendMaxAmount: tx.sendMaxAmount,
                                   isDeposit: tx.isDeposit,
                                   transactionType: tx.transactionType,
                                   fromAddress: tx.fromAddress,
                                   feeMode: tx.feeMode)
        if let localCacheItem =  self.localCache.get(cacheKey) {
            // use the cache item
            if localCacheItem.date.addingTimeInterval(getCacheSeconds(chain: tx.coin.chain)) > Date() {
                return localCacheItem.blockSpecific
            }
        }
        
        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
        
        print("🔌 BlockChainService: Fetching gas info for chain: \(tx.coin.chain.rawValue), ticker: \(tx.coin.ticker)")
        print("🔌 BlockChainService: Address: \(tx.coin.address), Fee mode: \(tx.feeMode)")
        
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(
            fromAddress: tx.coin.address,
            mode: tx.feeMode
        )
        
        print("🔌 BlockChainService: Got gas price: \(gasPrice), priority fee: \(priorityFee), nonce: \(nonce)")
        
        print("🔌 BlockChainService: Estimating gas limit for \(tx.coin.isNativeToken ? "native token" : "ERC20 token")")
        
        let estimateGasLimit = tx.coin.isNativeToken ?
        try await estimateGasLimit(tx: tx, gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce) :
        await estimateERC20GasLimit(tx: tx, gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce)
        
        print("🔌 BlockChainService: Estimated gas limit: \(estimateGasLimit)")
        
        let defaultGasLimit = BigInt(EVMHelper.defaultERC20TransferGasUnit)
        print("🔌 BlockChainService: Default gas limit: \(defaultGasLimit)")
        
        let gasLimit = max(defaultGasLimit, estimateGasLimit)
        print("🔌 BlockChainService: Final gas limit: \(gasLimit)")
        
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
            feeMode: tx.feeMode
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
                       feeMode: FeeMode) async throws -> BlockChainSpecific {
        switch coin.chain {
            
        case .zcash:
            return .UTXO(byteFee: coin.feeDefault.toBigInt(), sendMaxAmount: sendMaxAmount)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let byteFeeValue: BigInt
            if let byteFee, !byteFee.isZero {
                byteFeeValue = byteFee
            } else {
                byteFeeValue = try await fetchUTXOFee(coin: coin, action: action, feeMode: feeMode)
            }
            return .UTXO(byteFee: byteFeeValue, sendMaxAmount: sendMaxAmount)
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
            return .THORChain(accountNumber: accountNumber, sequence: sequence, fee: fee, isDeposit: isDeposit)
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
            
            if let fromAddress, let toAddress, !toAddress.isEmpty, !coin.isNativeToken {
                async let associatedTokenAddressFromPromise = sol.fetchTokenAssociatedAccountByOwner(for: fromAddress, mintAddress: coin.contractAddress)
                async let associatedTokenAddressToPromise = sol.fetchTokenAssociatedAccountByOwner(for: toAddress, mintAddress: coin.contractAddress)
                let (associatedTokenAddressFrom, _) = try await associatedTokenAddressFromPromise
                let (associatedTokenAddressTo, isToken2022) = try await associatedTokenAddressToPromise
                
                return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: associatedTokenAddressFrom, toAddressPubKey: associatedTokenAddressTo, hasProgramId: isToken2022)
            }
            
            return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)
            
        case .sui:
            let (referenceGasPrice, allCoins) = try await sui.getGasInfo(coin: coin)
            return .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins)
            
        case .polkadot:
            let gasInfo = try await dot.getGasInfo(fromAddress: coin.address)
            return .Polkadot(recentBlockHash: gasInfo.recentBlockHash, nonce: UInt64(gasInfo.nonce), currentBlockNumber: gasInfo.currentBlockNumber, specVersion: gasInfo.specVersion, transactionVersion: gasInfo.transactionVersion, genesisHash: gasInfo.genesisHash)
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain,.ethereumSepolia:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            let baseFee = try await service.getBaseFee()
            let (_, defaultPriorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address, mode: feeMode)
            
            let gasLimit = gasLimit ?? normalizeGasLimit(coin: coin, action: action)
            let priorityFeesMap = try await service.fetchMaxPriorityFeesPerGas()
            let priorityFee = priorityFeesMap[feeMode] ?? 0
            let normalizedPriorityFee = max(priorityFee, defaultPriorityFee)
            let normalizedBaseFee = Self.normalizeEVMFee(baseFee)
            let maxFeePerGasWei = normalizedBaseFee + normalizedPriorityFee
            return .Ethereum(maxFeePerGasWei: maxFeePerGasWei, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit)
            
        case .zksync:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            let (gasLimit, _, maxFeePerGas, maxPriorityFeePerGas, nonce) = try await service.getGasInfoZk(fromAddress: coin.address, toAddress: .zeroAddress)
            
            return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: maxPriorityFeePerGas, nonce: nonce, gasLimit: gasLimit)
            
        case .gaiaChain:
            let account = try await atom.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            var ibcDenomTrace: CosmosIbcDenomTraceDenomTrace? = nil
            if coin.contractAddress.contains("ibc/"), let denomTrace = await atom.fetchIbcDenomTraces(coin: coin) {
                ibcDenomTrace = denomTrace
            }
            
            let now = Date()
            let tenMinutesFromNow = now.addingTimeInterval(10 * 60) // Add 10 minutes to current time
            let timeoutInNanoseconds = UInt64(tenMinutesFromNow.timeIntervalSince1970 * 1_000_000_000)
            
            let latestBlock = try await atom.fetchLatestBlock(coin: coin)
            ibcDenomTrace?.height = "\(latestBlock)_\(timeoutInNanoseconds)"
            
            if ibcDenomTrace == nil {
                ibcDenomTrace = CosmosIbcDenomTraceDenomTrace(path: "", baseDenom: "", height: "\(latestBlock)_\(timeoutInNanoseconds)")
            }
            
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue, ibcDenomTrace: ibcDenomTrace)
        case .kujira:
            let account = try await kuji.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            var ibcDenomTrace: CosmosIbcDenomTraceDenomTrace? = nil
            if coin.contractAddress.contains("ibc/"), let denomTrace = await kuji.fetchIbcDenomTraces(coin: coin) {
                ibcDenomTrace = denomTrace
            }
            
            let now = Date()
            let tenMinutesFromNow = now.addingTimeInterval(10 * 60) // Add 10 minutes to current time
            let timeoutInNanoseconds = UInt64(tenMinutesFromNow.timeIntervalSince1970 * 1_000_000_000)
            
            let latestBlock = try await kuji.fetchLatestBlock(coin: coin)
            ibcDenomTrace?.height = "\(latestBlock)_\(timeoutInNanoseconds)"
            
            if ibcDenomTrace == nil {
                ibcDenomTrace = CosmosIbcDenomTraceDenomTrace(path: "", baseDenom: "", height: "\(latestBlock)_\(timeoutInNanoseconds)")
            }
            
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue, ibcDenomTrace: ibcDenomTrace)
        case .osmosis:
            let account = try await osmo.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            var ibcDenomTrace: CosmosIbcDenomTraceDenomTrace? = nil
            if coin.contractAddress.contains("ibc/"), let denomTrace = await osmo.fetchIbcDenomTraces(coin: coin) {
                ibcDenomTrace = denomTrace
            }
            
            let now = Date()
            let tenMinutesFromNow = now.addingTimeInterval(10 * 60) // Add 10 minutes to current time
            let timeoutInNanoseconds = UInt64(tenMinutesFromNow.timeIntervalSince1970 * 1_000_000_000)
            
            let latestBlock = try await osmo.fetchLatestBlock(coin: coin)
            ibcDenomTrace?.height = "\(latestBlock)_\(timeoutInNanoseconds)"
            
            if ibcDenomTrace == nil {
                ibcDenomTrace = CosmosIbcDenomTraceDenomTrace(path: "", baseDenom: "", height: "\(latestBlock)_\(timeoutInNanoseconds)")
            }
            
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue, ibcDenomTrace: ibcDenomTrace)
        case .terra:
            let account = try await terra.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            var ibcDenomTrace: CosmosIbcDenomTraceDenomTrace? = nil
            if coin.contractAddress.contains("ibc/"), let denomTrace = await terra.fetchIbcDenomTraces(coin: coin) {
                ibcDenomTrace = denomTrace
            }
            
            let now = Date()
            let tenMinutesFromNow = now.addingTimeInterval(10 * 60) // Add 10 minutes to current time
            let timeoutInNanoseconds = UInt64(tenMinutesFromNow.timeIntervalSince1970 * 1_000_000_000)
            
            let latestBlock = try await kuji.fetchLatestBlock(coin: coin)
            ibcDenomTrace?.height = "\(latestBlock)_\(timeoutInNanoseconds)"
            
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue, ibcDenomTrace: ibcDenomTrace)
            
            
        case .terraClassic:
            let account = try await terraClassic.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 100000000, transactionType: transactionType.rawValue, ibcDenomTrace: nil)
            
        case .dydx:
            let account = try await dydx.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 2500000000000000, transactionType: transactionType.rawValue, ibcDenomTrace: nil)
            
        case .noble:
            let account = try await noble.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 20000, transactionType: transactionType.rawValue, ibcDenomTrace: nil)
            
        case .ton:
            let (seqno, expireAt) = try await ton.getSpecificTransactionInfo(coin)
            return .Ton(sequenceNumber: seqno, expireAt: expireAt, bounceable: false, sendMaxAmount: sendMaxAmount)
        case .ripple:
            
            let account = try await ripple.fetchAccountsInfo(for: coin.address)
            
            let sequence = account?.result?.accountData?.sequence ?? 0
            
            let lastLedgerSequence = account?.result?.ledgerCurrentIndex ?? 0
            
            //60 is bc of tss to wait till 5min so all devices can sign.
            return .Ripple(sequence: UInt64(sequence), gas: 180000, lastLedgerSequence: UInt64(lastLedgerSequence) + 60)
            
        case .akash:
            let account = try await akash.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 3000, transactionType: transactionType.rawValue, ibcDenomTrace: nil)
        case .tron:
            return try await tron.getBlockInfo(coin: coin)
        }
    }
    
    func normalizeGasLimit(coin: Coin, action: Action) -> BigInt {
        switch action {
        case .transfer:
            return BigInt(coin.feeDefault) ?? 0
        case .swap:
            return BigInt(EVMHelper.defaultETHSwapGasUnit)
        }
    }
    
    func estimateERC20GasLimit(
        tx: SendTransaction,
        gasPrice: BigInt,
        priorityFee: BigInt,
        nonce: Int64
    ) async  -> BigInt {
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
            print("failed to estimate ERC20 transfer gas limit : \(error)")
            return 0
        }
    }
    
    func estimateGasLimit(
        tx: SendTransaction,
        gasPrice: BigInt,
        priorityFee: BigInt,
        nonce: Int64
    ) async throws -> BigInt {
        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
        let gas = try await service.estimateGasForEthTransaction(
            senderAddress: tx.coin.address,
            recipientAddress: .anyAddress,
            value: tx.amountInRaw,
            memo: tx.memo
        )
        return gas
    }
}
