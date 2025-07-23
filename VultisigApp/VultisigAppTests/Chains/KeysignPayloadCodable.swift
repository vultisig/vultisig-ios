//
//  KeysignPayloadCodable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 23/7/2025.
//

import Foundation
import VultisigCommonData

extension VSCoin: Codable {
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
        chain = try container.decode(String.self, forKey: .chain)
        ticker = try container.decode(String.self, forKey: .ticker)
        address = try container.decode(String.self, forKey: .address)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        decimals = try container.decode(Int32.self, forKey: .decimals)
        priceProviderID = try container.decode(String.self, forKey: .priceProviderID)
        isNativeToken = try container.decode(Bool.self, forKey: .isNativeToken)
        hexPublicKey = try container.decode(String.self, forKey: .hexPublicKey)
        logo = try container.decode(String.self, forKey: .logo)
    }
}

extension VSUTXOSpecific: Codable {
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
        byteFee = try container.decode(String.self, forKey: .byteFee)
        sendMaxAmount = try container.decode(Bool.self, forKey: .sendMaxAmount)
    }
}

extension VSCardanoChainSpecific: Codable {
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
        byteFee = try container.decode(Int64.self, forKey: .byteFee)
        sendMaxAmount = try container.decode(Bool.self, forKey: .sendMaxAmount)
        ttl = try container.decode(UInt64.self, forKey: .ttl)
    }
}

extension VSEthereumSpecific: Codable {
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
        maxFeePerGasWei = try container.decode(String.self, forKey: .maxFeePerGasWei)
        priorityFee = try container.decode(String.self, forKey: .priorityFee)
        nonce = try container.decode(Int64.self, forKey: .nonce)
        gasLimit = try container.decode(String.self, forKey: .gasLimit)
    }
}

extension VSTHORChainSpecific: Codable {
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
        accountNumber = try container.decode(UInt64.self, forKey: .accountNumber)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        fee = try container.decode(UInt64.self, forKey: .fee)
        isDeposit = try container.decode(Bool.self, forKey: .isDeposit)
        let transactionTypeRaw = try container.decode(String.self, forKey: .transactionType)
    }
}

extension VSMAYAChainSpecific: Codable {
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
        accountNumber = try container.decode(UInt64.self, forKey: .accountNumber)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        isDeposit = try container.decode(Bool.self, forKey: .isDeposit)
    }
}
extension VSCosmosIbcInfo: Codable {
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
        sourcePort = try container.decode(String.self, forKey: .sourcePort)
        sourceChannel = try container.decode(String.self, forKey: .sourceChannel)
        revisionNumber = try container.decode(UInt64.self, forKey: .revisionNumber)
        revisionHeight = try container.decode(UInt64.self, forKey: .revisionHeight)
    }
}

extension VSCosmosIbcDenomTrace: Codable {
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
        path = try container.decode(String.self, forKey: .path)
        baseDenom = try container.decode(String.self, forKey: .baseDenom)
        latestBlock = try container.decode(String.self, forKey: .latestBlock)
    }
}

extension VSCosmosSpecific: Codable {
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
        
    }
}

extension VSKeysignPayload: Codable {
    enum CodingKeys: String, CodingKey {
        case coin
        case toAddress = "to_address"
        case toAmount = "to_amount"
        case blockchainSpecific = "BlockchainSpecific"
        case utxos
        case memo
        case swapPayload = "SwapPayload"
        case approvePayload = "approve_payload"
        case vaultPubKeyECDSA = "vault_pub_key_ecdsa"
        case vaultLocalPartyID = "vault_local_party_id"
        case libType = "lib_type"
    }
    
    public func encode(to encoder: any Encoder) throws {
        
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(VSCoin.self, forKey: .coin)
        toAddress = try container.decode(String.self, forKey: .toAddress)
        toAmount = try container.decode(String.self, forKey: .toAmount)
        chainSpecific = try container.decode(String.self, forKey: .blockchainSpecific)
        utxos = try container.decode([String].self, forKey: .utxos)
        memo = try container.decode(String.self, forKey: .memo)
        swapPayload = try container.decodeIfPresent(String.self, forKey: .swapPayload)
        approvePayload = try container.decodeIfPresent(.self, forKey: .approvePayload)
        vaultPubKeyECDSA = try container.decode(String.self, forKey: .vaultPubKeyECDSA)
        vaultLocalPartyID = try container.decode(String.self, forKey: .vaultLocalPartyID)
        libType = try container.decode(String.self, forKey: .libType)
    }
}
