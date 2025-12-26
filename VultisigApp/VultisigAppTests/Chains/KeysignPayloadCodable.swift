//
//  KeysignPayloadCodable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 23/7/2025.
//

import Foundation
import VultisigCommonData

extension VSCoin: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case chain
        case ticker
        case address
        case contractAddress = "contract_address"
        case decimals
        case priceProviderID = "price_provider_id"
        case isNativeToken = "is_native_token"
        case hexPublicKey = "hex_public_key"
        case logo
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(address, forKey: .address)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(decimals, forKey: .decimals)
        try container.encode(priceProviderID, forKey: .priceProviderID)
        try container.encode(isNativeToken, forKey: .isNativeToken)
        try container.encode(hexPublicKey, forKey: .hexPublicKey)
        try container.encode(logo, forKey: .logo)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        chain = try container.decode(String.self, forKey: .chain)
        ticker = try container.decode(String.self, forKey: .ticker)
        address = try container.decode(String.self, forKey: .address)
        contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress) ?? String()
        decimals = try container.decode(Int32.self, forKey: .decimals)
        priceProviderID = try container.decode(String.self, forKey: .priceProviderID)
        isNativeToken = try container.decode(Bool.self, forKey: .isNativeToken)
        hexPublicKey = try container.decode(String.self, forKey: .hexPublicKey)
        logo = try container.decodeIfPresent(String.self, forKey: .logo) ?? String()
    }
}

extension VSUTXOSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case byteFee = "byte_fee"
        case sendMaxAmount = "send_max_amount"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byteFee, forKey: .byteFee)
        try container.encode(sendMaxAmount, forKey: .sendMaxAmount)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        byteFee = try container.decode(String.self, forKey: .byteFee)
        if container.contains(.sendMaxAmount) {
            sendMaxAmount = try container.decode(Bool.self, forKey: .sendMaxAmount)
        }
    }
}

extension VSCardanoChainSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case byteFee = "byte_fee"
        case sendMaxAmount = "send_max_amount"
        case ttl = "ttl"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byteFee, forKey: .byteFee)
        try container.encode(sendMaxAmount, forKey: .sendMaxAmount)
        try container.encode(ttl, forKey: .ttl)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        byteFee = try container.decode(Int64.self, forKey: .byteFee)
        sendMaxAmount = try container.decode(Bool.self, forKey: .sendMaxAmount)
        ttl = try container.decode(UInt64.self, forKey: .ttl)
    }
}

extension VSEthereumSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case maxFeePerGasWei = "max_fee_per_gas_wei"
        case priorityFee = "priority_fee"
        case nonce  = "nonce"
        case gasLimit = "gas_limit"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxFeePerGasWei, forKey: .maxFeePerGasWei)
        try container.encode(priorityFee, forKey: .priorityFee)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(gasLimit, forKey: .gasLimit)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        maxFeePerGasWei = try container.decode(String.self, forKey: .maxFeePerGasWei)
        priorityFee = try container.decode(String.self, forKey: .priorityFee)
        nonce = try container.decode(Int64.self, forKey: .nonce)
        gasLimit = try container.decode(String.self, forKey: .gasLimit)
    }
}

extension VSTHORChainSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case accountNumber = "account_number"
        case sequence = "sequence"
        case fee = "fee"
        case isDeposit = "is_deposit"
        case transactionType = "transaction_type"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountNumber, forKey: .accountNumber)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(fee, forKey: .fee)
        try container.encode(isDeposit, forKey: .isDeposit)
        try container.encode(transactionType.rawValue, forKey: .transactionType)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        accountNumber = try container.decode(UInt64.self, forKey: .accountNumber)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        fee = try container.decode(UInt64.self, forKey: .fee)
        isDeposit = try container.decode(Bool.self, forKey: .isDeposit)
        if container.contains(.transactionType) {
            let transactionTypeRaw = try container.decode(Int.self, forKey: .transactionType)
            transactionType = VSTransactionType(rawValue: transactionTypeRaw) ?? .unspecified
        }
    }
}

extension VSMAYAChainSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case accountNumber = "account_number"
        case sequence = "sequence"
        case isDeposit = "is_deposit"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountNumber, forKey: .accountNumber)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(isDeposit, forKey: .isDeposit)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        accountNumber = try container.decode(UInt64.self, forKey: .accountNumber)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        isDeposit = try container.decode(Bool.self, forKey: .isDeposit)
    }
}
extension VSCosmosIbcInfo: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case sourcePort = "source_port"
        case sourceChannel = "source_channel"
        case revisionNumber = "revision_number"
        case revisionHeight = "revision_height"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePort, forKey: .sourcePort)
        try container.encode(sourceChannel, forKey: .sourceChannel)
        try container.encode(revisionNumber, forKey: .revisionNumber)
        try container.encode(revisionHeight, forKey: .revisionHeight)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        sourcePort = try container.decode(String.self, forKey: .sourcePort)
        sourceChannel = try container.decode(String.self, forKey: .sourceChannel)
        revisionNumber = try container.decode(UInt64.self, forKey: .revisionNumber)
        revisionHeight = try container.decode(UInt64.self, forKey: .revisionHeight)
    }
}

extension VSCosmosIbcDenomTrace: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case path
        case baseDenom = "base_denom"
        case latestBlock = "latest_block"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(baseDenom, forKey: .baseDenom)
        try container.encode(latestBlock, forKey: .latestBlock)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        path = try container.decode(String.self, forKey: .path)
        baseDenom = try container.decode(String.self, forKey: .baseDenom)
        latestBlock = try container.decode(String.self, forKey: .latestBlock)
    }
}

extension VSCosmosSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case accountNumber = "account_number"
        case sequence = "sequence"
        case gas = "gas"
        case transactionType = "transaction_type"
        case ibcDenomTraces = "ibc_denom_traces"
        case ibcInfo = "ibc_info"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountNumber, forKey: .accountNumber)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(gas, forKey: .gas)
        try container.encode(transactionType.rawValue, forKey: .transactionType)
        try container.encodeIfPresent(ibcDenomTraces, forKey: .ibcDenomTraces)
        try container.encodeIfPresent(ibcInfo, forKey: .ibcInfo)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        accountNumber = try container.decode(UInt64.self, forKey: .accountNumber)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        gas = try container.decode(UInt64.self, forKey: .gas)
        let transactionTypeRaw = try container.decode(Int.self, forKey: .transactionType)
        transactionType = VSTransactionType(rawValue: transactionTypeRaw) ?? .unspecified
        let tmpIbcDenomTraces = try container.decodeIfPresent(VSCosmosIbcDenomTrace.self, forKey: .ibcDenomTraces)
        if let tmpIbcDenomTraces {
            ibcDenomTraces = tmpIbcDenomTraces
        }
        let tmpIbcInfo = try container.decodeIfPresent(VSCosmosIbcInfo.self, forKey: .ibcInfo)
        if let tmpIbcInfo {
            ibcInfo = tmpIbcInfo
        }
    }
}

extension VSSolanaSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case recentBlockHash = "recent_block_hash"
        case priorityFee = "priority_fee"
        case fromTokenAssociatedAddress = "from_token_associated_address"
        case toTokenAssociatedAddress = "to_token_associated_address"
        case programID = "program_id"
        case priorityLimit = "priority_limit"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recentBlockHash, forKey: .recentBlockHash)
        try container.encode(priorityFee, forKey: .priorityFee)
        try container.encode(fromTokenAssociatedAddress, forKey: .fromTokenAssociatedAddress)
        try container.encode(toTokenAssociatedAddress, forKey: .toTokenAssociatedAddress)
        try container.encode(programID, forKey: .programID)
        if hasComputeLimit {
            try container.encode(computeLimit, forKey: .priorityLimit)
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        recentBlockHash = try container.decode(String.self, forKey: .recentBlockHash)
        priorityFee = try container.decode(String.self, forKey: .priorityFee)
        fromTokenAssociatedAddress = try container.decodeIfPresent(String.self, forKey: .fromTokenAssociatedAddress) ?? String()
        toTokenAssociatedAddress = try container.decodeIfPresent(String.self, forKey: .toTokenAssociatedAddress) ?? String()
        programID = try container.decodeIfPresent(Bool.self, forKey: .programID) ?? false
        if let priorityLimitStr = try container.decodeIfPresent(String.self, forKey: .priorityLimit) {
            computeLimit = priorityLimitStr
        }
    }
}

extension VSPolkadotSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case recentBlockHash = "recent_block_hash"
        case nonce
        case currentBlockNumber = "current_block_number"
        case specVersion = "spec_version"
        case transactionVersion = "transaction_version"
        case genesisHash = "genesis_hash"
        case gas
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recentBlockHash, forKey: .recentBlockHash)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(currentBlockNumber, forKey: .currentBlockNumber)
        try container.encode(specVersion, forKey: .specVersion)
        try container.encode(transactionVersion, forKey: .transactionVersion)
        try container.encode(genesisHash, forKey: .genesisHash)
        try container.encode(gas, forKey: .gas)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        recentBlockHash = try container.decode(String.self, forKey: .recentBlockHash)
        nonce = try container.decode(UInt64.self, forKey: .nonce)
        currentBlockNumber = try container.decode(String.self, forKey: .currentBlockNumber)
        specVersion = try container.decode(UInt32.self, forKey: .specVersion)
        transactionVersion = try container.decode(UInt32.self, forKey: .transactionVersion)
        genesisHash = try container.decode(String.self, forKey: .genesisHash)
        gas = try container.decodeIfPresent(UInt64.self, forKey: .gas) ?? 0
    }
}
extension VSSuiCoin: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case coinType = "coin_type"
        case coinObjectID = "coin_object_id"
        case version = "version"
        case digest = "digest"
        case balance = "balance"
        case previousTransaction = "previous_transaction"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coinType, forKey: .coinType)
        try container.encode(coinObjectID, forKey: .coinObjectID)
        try container.encode(version, forKey: .version)
        try container.encode(digest, forKey: .digest)
        try container.encode(balance, forKey: .balance)
        try container.encode(previousTransaction, forKey: .previousTransaction)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        coinType = try container.decode(String.self, forKey: .coinType)
        coinObjectID = try container.decode(String.self, forKey: .coinObjectID)
        version = try container.decode(String.self, forKey: .version)
        digest = try container.decode(String.self, forKey: .digest)
        balance = try container.decode(String.self, forKey: .balance)
        if container.contains(.previousTransaction) {
            previousTransaction = try container.decode(String.self, forKey: .previousTransaction)
        }
    }
}

extension VSSuiSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case referenceGasPrice = "reference_gas_price"
        case coins = "coins"
        case gasBudget = "gas_budget"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceGasPrice, forKey: .referenceGasPrice)
        try container.encode(coins, forKey: .coins)
        try container.encode(gasBudget, forKey: .gasBudget)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        referenceGasPrice = try container.decode(String.self, forKey: .referenceGasPrice)
        coins = try container.decode([VSSuiCoin].self, forKey: .coins)
        gasBudget = try container.decode(String.self, forKey: .gasBudget)
    }
}

extension VSTonSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case sequenceNumber = "sequence_number"
        case expireAt = "expire_at"
        case bounceable = "bounceable"
        case sendMaxAmount = "send_max_amount"
        // Support both iOS and Android JSON field names
        case jettonAddress = "jetton_address"
        case jettonsAddress = "jettons_address"
        case isActiveDestination = "is_active_destination"
        case isActive = "is_active"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(expireAt, forKey: .expireAt)
        try container.encode(bounceable, forKey: .bounceable)
        try container.encode(sendMaxAmount, forKey: .sendMaxAmount)
        // These fields might not exist in the current protobuf version
        try container.encodeIfPresent(jettonAddress, forKey: .jettonAddress)
        try container.encodeIfPresent(isActiveDestination, forKey: .isActiveDestination)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        sequenceNumber = try container.decode(UInt64.self, forKey: .sequenceNumber)
        expireAt = try container.decode(UInt64.self, forKey: .expireAt)
        bounceable = try container.decode(Bool.self, forKey: .bounceable)
        sendMaxAmount = try container.decode(Bool.self, forKey: .sendMaxAmount)
        // These fields might not exist in the current protobuf version, so use defaults
        // Accept both "jetton_address" and Android's "jettons_address"
        if let v = try container.decodeIfPresent(String.self, forKey: .jettonAddress) {
            jettonAddress = v
        } else if let v = try container.decodeIfPresent(String.self, forKey: .jettonsAddress) {
            jettonAddress = v
        } else {
            jettonAddress = ""
        }
        // Accept both "is_active_destination" and Android's "is_active"
        if let v = try container.decodeIfPresent(Bool.self, forKey: .isActiveDestination) {
            isActiveDestination = v
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .isActive) {
            isActiveDestination = v
        } else {
            isActiveDestination = false
        }
    }
}

extension VSRippleSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case sequence = "sequence"
        case gas
        case lastLedgerSequence = "last_ledger_sequence"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(gas, forKey: .gas)
        try container.encode(lastLedgerSequence, forKey: .lastLedgerSequence)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        gas = try container.decode(UInt64.self, forKey: .gas)
        lastLedgerSequence = try container.decode(UInt64.self, forKey: .lastLedgerSequence)
    }
}
extension VSTronSpecific: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case timestamp = "timestamp"
        case expiration = "expiration"
        case blockHeaderTimestamp = "block_header_timestamp"
        case blockHeaderNumber = "block_header_number"
        case blockHeaderVersion = "block_header_version"
        case blockHeaderTxTrieRoot = "block_header_tx_trie_root"
        case blockHeaderParentHash = "block_header_parent_hash"
        case blockHeaderWitnessAddress = "block_header_witness_address"
        case gasEstimation = "gas_estimation"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(expiration, forKey: .expiration)
        try container.encode(blockHeaderTimestamp, forKey: .blockHeaderTimestamp)
        try container.encode(blockHeaderNumber, forKey: .blockHeaderNumber)
        try container.encode(blockHeaderVersion, forKey: .blockHeaderVersion)
        try container.encode(blockHeaderTxTrieRoot, forKey: .blockHeaderTxTrieRoot)
        try container.encode(blockHeaderParentHash, forKey: .blockHeaderParentHash)
        try container.encode(blockHeaderWitnessAddress, forKey: .blockHeaderWitnessAddress)
        try container.encode(gasEstimation, forKey: .gasEstimation)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        expiration = try container.decode(UInt64.self, forKey: .expiration)
        blockHeaderTimestamp = try container.decode(UInt64.self, forKey: .blockHeaderTimestamp)
        blockHeaderNumber = try container.decode(UInt64.self, forKey: .blockHeaderNumber)
        blockHeaderVersion = try container.decode(UInt64.self, forKey: .blockHeaderVersion)
        blockHeaderTxTrieRoot = try container.decode(String.self, forKey: .blockHeaderTxTrieRoot)
        blockHeaderParentHash = try container.decode(String.self, forKey: .blockHeaderParentHash)
        blockHeaderWitnessAddress = try container.decode(String.self, forKey: .blockHeaderWitnessAddress)
        gasEstimation = try container.decode(UInt64.self, forKey: .gasEstimation)
    }
}

extension VSUtxoInfo: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case hash
        case amount
        case index
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hash, forKey: .hash)
        try container.encode(amount, forKey: .amount)
        try container.encode(index, forKey: .index)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        hash = try container.decode(String.self, forKey: .hash)
        amount = try container.decode(Int64.self, forKey: .amount)
        index = try container.decode(UInt32.self, forKey: .index)
    }
}

extension VSTHORChainSwapPayload: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case fromAddress = "from_address"
        case fromCoin = "from_coin"
        case toCoin = "to_coin"
        case vaultAddress = "vault_address"
        case routerAddress = "router_address"
        case fromAmount = "from_amount"
        case toAmountDecimal = "to_amount_decimal"
        case toAmountLimit = "to_amount_limit"
        case streamingInterval = "streaming_interval"
        case streamingQuantity = "streaming_quantity"
        case isAffiliate = "is_affiliate"
        case fee = "fee"
        case expirationTime = "expiration_time"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromAddress, forKey: .fromAddress)
        try container.encode(fromCoin, forKey: .fromCoin)
        try container.encode(toCoin, forKey: .toCoin)
        try container.encode(vaultAddress, forKey: .vaultAddress)
        try container.encode(routerAddress, forKey: .routerAddress)
        try container.encode(fromAmount, forKey: .fromAmount)
        try container.encode(toAmountDecimal, forKey: .toAmountDecimal)
        try container.encode(toAmountLimit, forKey: .toAmountLimit)
        try container.encode(streamingInterval, forKey: .streamingInterval)
        try container.encode(streamingQuantity, forKey: .streamingQuantity)
        try container.encode(isAffiliate, forKey: .isAffiliate)
        try container.encode(fee, forKey: .fee)
        try container.encode(expirationTime, forKey: .expirationTime)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fromAddress = try container.decode(String.self, forKey: .fromAddress)
        fromCoin = try container.decode(VSCoin.self, forKey: .fromCoin)
        toCoin = try container.decode(VSCoin.self, forKey: .toCoin)
        vaultAddress = try container.decode(String.self, forKey: .vaultAddress)
        routerAddress = try container.decodeIfPresent(String.self, forKey: .routerAddress) ?? String()
        fromAmount = try container.decode(String.self, forKey: .fromAmount)
        toAmountDecimal = try container.decode(String.self, forKey: .toAmountDecimal)
        toAmountLimit = try container.decode(String.self, forKey: .toAmountLimit)
        streamingInterval = try container.decode(String.self, forKey: .streamingInterval)
        streamingQuantity = try container.decode(String.self, forKey: .streamingQuantity)
        isAffiliate = try container.decode(Bool.self, forKey: .isAffiliate)
        fee = try container.decode(String.self, forKey: .fee)
        expirationTime = try container.decode(UInt64.self, forKey: .expirationTime)
    }
}
extension VSErc20ApprovePayload : @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case amount
        case spender
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encode(spender, forKey: .spender)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        amount = try container.decode(String.self, forKey: .amount)
        spender = try container.decode(String.self, forKey: .spender)
    }
}
extension VSOneInchTransaction: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case data
        case value
        case gasPrice = "gas_price"
        case gas
        case swapFee = "swap_fee"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(data, forKey: .data)
        try container.encode(value, forKey: .value)
        try container.encode(gasPrice, forKey: .gasPrice)
        try container.encode(gas, forKey: .gas)
        try container.encode(swapFee, forKey: .swapFee)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? String()
        to = try container.decodeIfPresent(String.self, forKey: .to) ?? String()
        data = try container.decodeIfPresent(String.self, forKey: .data) ?? String()
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? String()
        gasPrice = try container.decodeIfPresent(String.self, forKey: .gasPrice) ?? String()
        gas = try container.decode(Int64.self, forKey: .gas)
        swapFee = try container.decodeIfPresent(String.self, forKey: .swapFee) ?? String()
    }
}

extension VSOneInchQuote: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case dstAmount = "dst_amount"
        case tx
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dstAmount, forKey: .dstAmount)
        if hasTx{
            try container.encode(tx, forKey: .tx)
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        dstAmount = try container.decode(String.self, forKey: .dstAmount)
        if container.contains(.tx) {
            tx = try container.decode(VSOneInchTransaction.self, forKey: .tx)
        }
    }
}

extension VSOneInchSwapPayload : @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case fromCoin = "from_coin"
        case toCoin = "to_coin"
        case fromAmount = "from_amount"
        case toAmountDecimal = "to_amount_decimal"
        case quote
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromCoin, forKey: .fromCoin)
        try container.encode(toCoin, forKey: .toCoin)
        try container.encode(fromAmount, forKey: .fromAmount)
        try container.encode(toAmountDecimal, forKey: .toAmountDecimal)
        try container.encode(quote, forKey: .quote)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fromCoin = try container.decode(VSCoin.self, forKey: .fromCoin)
        toCoin = try container.decode(VSCoin.self, forKey: .toCoin)
        fromAmount = try container.decode(String.self, forKey: .fromAmount)
        toAmountDecimal = try container.decode(String.self, forKey: .toAmountDecimal)
        quote = try container.decode(VSOneInchQuote.self, forKey: .quote)
    }
}
extension VSKyberSwapTransaction: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case data
        case value
        case gasPrice = "gas_price"
        case gas
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(data, forKey: .data)
        try container.encode(value, forKey: .value)
        try container.encode(gasPrice, forKey: .gasPrice)
        try container.encode(gas, forKey: .gas)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? String()
        to = try container.decodeIfPresent(String.self, forKey: .to) ?? String()
        data = try container.decodeIfPresent(String.self, forKey: .data) ?? String()
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? String()
        gasPrice = try container.decodeIfPresent(String.self, forKey: .gasPrice) ?? String()
        gas = try container.decode(Int64.self, forKey: .gas)
    }
}
extension VSKyberSwapQuote: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case dstAmount = "dst_amount"
        case tx
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dstAmount, forKey: .dstAmount)
        if hasTx{
            try container.encode(tx, forKey: .tx)
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        dstAmount = try container.decode(String.self, forKey: .dstAmount)
        if container.contains(.tx) {
            tx = try container.decode(VSKyberSwapTransaction.self, forKey: .tx)
        }
    }
}

extension VSKyberSwapPayload: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case fromCoin = "from_coin"
        case toCoin = "to_coin"
        case fromAmount = "from_amount"
        case toAmountDecimal = "to_amount_decimal"
        case quote
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromCoin, forKey: .fromCoin)
        try container.encode(toCoin, forKey: .toCoin)
        try container.encode(fromAmount, forKey: .fromAmount)
        try container.encode(toAmountDecimal, forKey: .toAmountDecimal)
        try container.encode(quote, forKey: .quote)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fromCoin = try container.decode(VSCoin.self, forKey: .fromCoin)
        toCoin = try container.decode(VSCoin.self, forKey: .toCoin)
        fromAmount = try container.decode(String.self, forKey: .fromAmount)
        toAmountDecimal = try container.decode(String.self, forKey: .toAmountDecimal)
        quote = try container.decode(VSKyberSwapQuote.self, forKey: .quote)
    }
}

extension VSCosmosCoin: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case denom
        case amount
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(denom, forKey: .denom)
        try container.encode(amount, forKey: .amount)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        denom = try container.decode(String.self, forKey: .denom)
        amount = try container.decode(String.self, forKey: .amount)
    }
    
}
extension VSWasmExecuteContractPayload: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case senderAddress = "sender_address"
        case contractAddress = "contract_address"
        case executeMsg = "execute_msg"
        case coins = "coins"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderAddress, forKey: .senderAddress)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(executeMsg, forKey: .executeMsg)
        try container.encode(coins, forKey: .coins)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        senderAddress = try container.decode(String.self, forKey: .senderAddress)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        executeMsg = try container.decode(String.self, forKey: .executeMsg)
        if container.contains(.coins) {
            coins = try container.decode([VSCosmosCoin].self, forKey: .coins)
        }
    }
}
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    
    init(_ string: String) {
        self.stringValue = string
    }
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        return nil
    }
}

extension VSKeysignPayload.OneOf_SignData: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case signDirect = "sign_direct"
        case signAmino = "sign_amino"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode signAmino first
        if container.contains(.signAmino) {
            let signAmino = try container.decode(VSSignAmino.self, forKey: .signAmino)
            self = .signAmino(signAmino)
        } else if container.contains(.signDirect) {
            let signDirect = try container.decode(VSSignDirect.self, forKey: .signDirect)
            self = .signDirect(signDirect)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to decode VSKeysignPayload.OneOf_SignData: no valid case found. Available keys: \(container.allKeys)"
                )
            )
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .signAmino(let vSSignAmino):
            try container.encode(vSSignAmino, forKey: .signAmino)
        case .signDirect(let vSSignDirect):
            try container.encode(vSSignDirect, forKey: .signDirect)
        }
    }
}

extension VSKeysignPayload: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case coin
        case toAddress = "to_address"
        case toAmount = "to_amount"
        case blockchainSpecific = "BlockchainSpecific"
        case utxoInfo = "utxo_info"
        case memo
        case swapPayload = "SwapPayload"
        case erc20ApprovePayload = "erc20_approve_payload"
        case vaultPubKeyECDSA = "vault_public_key_ecdsa"
        case vaultLocalPartyID = "vault_local_party_id"
        case libType = "lib_type"
        case wasmExecuteContractPayload = "wasm_execute_contract_payload"
        case signData = "sign_data"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coin, forKey: .coin)
        try container.encode(toAddress, forKey: .toAddress)
        try container.encode(toAmount, forKey: .toAmount)
        var blockchainSpecificContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .blockchainSpecific)
        // Encode blockchainSpecific based on its type
        switch blockchainSpecific {
        case .utxoSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("UtxoSpecific"))
        case .cardano(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("Cardano"))
        case .ethereumSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("EthereumSpecific"))
        case .thorchainSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("ThorchainSpecific"))
        case .mayaSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("MayaSpecific"))
        case .cosmosSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("CosmosSpecific"))
        case .solanaSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("SolanaSpecific"))
        case .polkadotSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("PolkadotSpecific"))
        case .suicheSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("SuicheSpecific"))
        case .tonSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("TonSpecific"))
        case .rippleSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("RippleSpecific"))
        case .tronSpecific(let specific):
            try blockchainSpecificContainer.encode(specific, forKey: DynamicCodingKey("TronSpecific"))
        case .none:
            print("No blockchain specific info to encode")
        }
        try container.encode(utxoInfo, forKey: .utxoInfo)
        try container.encode(memo, forKey: .memo)
        var swapPayloadContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .swapPayload)
        switch swapPayload{
        case .thorchainSwapPayload(let payload):
            try swapPayloadContainer.encode(payload, forKey: DynamicCodingKey("ThorchainSwapPayload"))
        case .kyberswapSwapPayload(let payload):
            try swapPayloadContainer.encode(payload, forKey: DynamicCodingKey("KyberswapSwapPayload"))
        case .oneinchSwapPayload(let payload):
            try swapPayloadContainer.encode(payload, forKey: DynamicCodingKey("OneinchSwapPayload"))
        case .mayachainSwapPayload(let payload):
            try swapPayloadContainer.encode(payload, forKey: DynamicCodingKey("MayachainSwapPayload"))
        case .none:
            print("No swap payload to encode")
        }
        
        
        try container.encodeIfPresent(erc20ApprovePayload, forKey: .erc20ApprovePayload)
        try container.encode(vaultPublicKeyEcdsa, forKey: .vaultPubKeyECDSA)
        try container.encode(vaultLocalPartyID, forKey: .vaultLocalPartyID)
        try container.encode(libType, forKey: .libType)
        try container.encode(signData, forKey: .signData)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        coin = try container.decode(VSCoin.self, forKey: .coin)
        toAddress = try container.decode(String.self, forKey: .toAddress)
        toAmount = try container.decode(String.self, forKey: .toAmount)
        // Decode blockchainSpecific
        let blockchainSpecificContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .blockchainSpecific)
        if let utxoSpecific = try? blockchainSpecificContainer.decode(VSUTXOSpecific.self, forKey: DynamicCodingKey("UtxoSpecific")) {
            blockchainSpecific = .utxoSpecific(utxoSpecific)
        } else if let cardanoSpecific = try? blockchainSpecificContainer.decode(VSCardanoChainSpecific.self, forKey: DynamicCodingKey("Cardano")) {
            blockchainSpecific = .cardano(cardanoSpecific)
        } else if let ethereumSpecific = try? blockchainSpecificContainer.decode(VSEthereumSpecific.self, forKey: DynamicCodingKey("EthereumSpecific")) {
            blockchainSpecific = .ethereumSpecific(ethereumSpecific)
        } else if let thorchainSpecific = try? blockchainSpecificContainer.decode(VSTHORChainSpecific.self, forKey: DynamicCodingKey("ThorchainSpecific")) {
            blockchainSpecific = .thorchainSpecific(thorchainSpecific)
        } else if let mayaSpecific = try? blockchainSpecificContainer.decode(VSMAYAChainSpecific.self, forKey: DynamicCodingKey("MayaSpecific")) {
            blockchainSpecific = .mayaSpecific(mayaSpecific)
        } else if let cosmosSpecific = try? blockchainSpecificContainer.decode(VSCosmosSpecific.self, forKey: DynamicCodingKey("CosmosSpecific")) {
            blockchainSpecific = .cosmosSpecific(cosmosSpecific)
        } else if let solanaSpecific = try? blockchainSpecificContainer.decode(VSSolanaSpecific.self, forKey: DynamicCodingKey("SolanaSpecific")) {
            blockchainSpecific = .solanaSpecific(solanaSpecific)
        } else if let polkadotSpecific = try? blockchainSpecificContainer.decode(VSPolkadotSpecific.self, forKey: DynamicCodingKey("PolkadotSpecific")) {
            blockchainSpecific = .polkadotSpecific(polkadotSpecific)
        } else if let suiSpecific = try? blockchainSpecificContainer.decode(VSSuiSpecific.self, forKey: DynamicCodingKey("SuicheSpecific")) {
            blockchainSpecific = .suicheSpecific(suiSpecific)
        } else if let tonSpecific = try? blockchainSpecificContainer.decode(VSTonSpecific.self, forKey: DynamicCodingKey("TonSpecific")) {
            blockchainSpecific = .tonSpecific(tonSpecific)
        } else if let rippleSpecific = try? blockchainSpecificContainer.decode(VSRippleSpecific.self, forKey: DynamicCodingKey("RippleSpecific")) {
            blockchainSpecific = .rippleSpecific(rippleSpecific)
        } else if let tronSpecific = try? blockchainSpecificContainer.decode(VSTronSpecific.self, forKey: DynamicCodingKey("TronSpecific")) {
            blockchainSpecific = .tronSpecific(tronSpecific)
        } else {
            blockchainSpecific = .none
        }
        
        utxoInfo = try container.decodeIfPresent([VSUtxoInfo].self, forKey: .utxoInfo) ?? []
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? String()
        // Inside the `init(from:)` method of `VSKeysignPayload`
        if let swapPayloadContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .swapPayload) {
            
            if let thorchainPayload = try? swapPayloadContainer.decode(VSTHORChainSwapPayload.self, forKey: DynamicCodingKey("ThorchainSwapPayload")) {
                swapPayload = .thorchainSwapPayload(thorchainPayload)
            } else if let kyberSwapPayload = try? swapPayloadContainer.decode(VSKyberSwapPayload.self, forKey: DynamicCodingKey("KyberswapSwapPayload")) {
                swapPayload = .kyberswapSwapPayload(kyberSwapPayload)
            } else if let oneInchPayload = try? swapPayloadContainer.decode(VSOneInchSwapPayload.self, forKey: DynamicCodingKey("OneinchSwapPayload")) {
                swapPayload = .oneinchSwapPayload(oneInchPayload)
            } else if let mayaPayload = try? swapPayloadContainer.decode(VSTHORChainSwapPayload.self, forKey: DynamicCodingKey("MayachainSwapPayload")) {
                swapPayload = .mayachainSwapPayload(mayaPayload)
            } else {
                swapPayload = .none
            }
        } else {
            swapPayload = .none
        }
        if container.contains(.erc20ApprovePayload) {
            erc20ApprovePayload = try container.decode(VSErc20ApprovePayload.self, forKey: .erc20ApprovePayload)
        }
        vaultPublicKeyEcdsa = try container.decode(String.self, forKey: .vaultPubKeyECDSA)
        vaultLocalPartyID = try container.decodeIfPresent(String.self, forKey: .vaultLocalPartyID) ?? String()
        libType = try container.decodeIfPresent(String.self, forKey: .libType) ?? "DKLS"
        if container.contains(.wasmExecuteContractPayload) {
            wasmExecuteContractPayload = try container.decode(VSWasmExecuteContractPayload.self, forKey: .wasmExecuteContractPayload)
        }
        
        if container.contains(.signData) {
            signData = try container.decode(VSKeysignPayload.OneOf_SignData.self, forKey: .signData)
        } else {
            signData = .none
        }
    }
}

extension VSSignDirect: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case bodyBytes = "body_bytes"
        case authInfoBytes = "auth_info_bytes"
        case chainID = "chain_id"
        case accountNumber = "account_number"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bodyBytes, forKey: .bodyBytes)
        try container.encode(authInfoBytes, forKey: .authInfoBytes)
        try container.encode(chainID, forKey: .chainID)
        try container.encode(accountNumber, forKey: .accountNumber)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        
        bodyBytes = try container.decode(String.self, forKey: .bodyBytes)
        authInfoBytes = try container.decode(String.self, forKey: .authInfoBytes)
        chainID = try container.decode(String.self, forKey: .chainID)
        accountNumber = try container.decode(String.self, forKey: .accountNumber)
    }
}

extension VSSignAmino: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case fee = "fee"
        case msgs = "msgs"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fee, forKey: .fee)
        try container.encode(msgs, forKey: .msgs)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fee = try container.decode(VSCosmosFee.self, forKey: .fee)
        msgs = try container.decode([VSCosmosMsg].self, forKey: .msgs)
    }
}

// Helper struct to decode any JSON value
private struct AnyCodableValue: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodableValue($0) })
        default:
            try container.encodeNil()
        }
    }
}

extension VSCosmosMsg: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case value
        
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        
        // Try to encode as JSON string if value contains JSON data
        if let jsonData = value.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
            let anyValue = AnyCodableValue(jsonObject)
            try container.encode(anyValue, forKey: .value)
        } else {
            try container.encode(value, forKey: .value)
        }
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        
        type = try container.decode(String.self, forKey: .type)
        
        // Try to decode as AnyCodableValue first to handle both dictionaries and strings
        if let anyValue = try? container.decode(AnyCodableValue.self, forKey: .value) {
            // Convert to JSON string
            if let jsonData = try? JSONSerialization.data(withJSONObject: anyValue.value, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                value = jsonString
            } else if let stringValue = anyValue.value as? String {
                value = stringValue
            } else {
                value = "{}"
            }
        } else {
            value = "{}"
        }
    }
}

extension VSCosmosFee: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case payer
        case granter
        case feePayer = "fee_payer"
        case amount
        case gas
        
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(payer, forKey: .payer)
        try container.encode(granter, forKey: .granter)
        try container.encode(feePayer, forKey: .feePayer)
        try container.encode(amount, forKey: .amount)
        try container.encode(gas, forKey: .gas)
        
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        
        payer = try container.decodeIfPresent(String.self, forKey: .payer) ?? String()
        granter = try container.decodeIfPresent(String.self, forKey: .granter) ?? String()
        feePayer = try container.decodeIfPresent(String.self, forKey: .feePayer) ?? String()
        amount = try container.decodeIfPresent([VSCosmosCoin].self, forKey: .amount) ?? []
        gas = try container.decode(String.self, forKey: .gas)
    }
}
