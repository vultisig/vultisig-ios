//
//  KeysignMessage+ProtoMappable.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.07.2024.
//

import Foundation
import BigInt
import VultisigCommonData

extension KeysignMessage: ProtoMappable {
    
    init(proto: VSKeysignMessage, vault: Vault) throws {
        self.sessionID = proto.sessionID
        self.serviceName = proto.serviceName
        self.payload = try KeysignPayload(proto: proto.keysignPayload, vault: vault)
        self.encryptionKeyHex = proto.encryptionKeyHex
        self.useVultisigRelay = proto.useVultisigRelay
    }
    
    func mapToProtobuff() -> VSKeysignMessage {
        return .with {
            $0.sessionID = sessionID
            $0.serviceName = serviceName
            $0.keysignPayload = payload.mapToProtobuff()
            $0.encryptionKeyHex = encryptionKeyHex
            $0.useVultisigRelay = useVultisigRelay
        }
    }
}

extension KeysignPayload: ProtoMappable {
    
    init(proto: VSKeysignPayload, vault: Vault) throws {
        guard let blockchainSpecific = proto.blockchainSpecific else {
            throw ProtoMappableError.blockchainSpecificNotFound
        }
        
        self.coin = try ProtoCoinResolver.resolve(vault: vault, coin: proto.coin)
        self.toAddress = proto.toAddress
        self.toAmount = BigInt(stringLiteral: proto.toAmount)
        self.chainSpecific = try BlockChainSpecific(proto: blockchainSpecific)
        self.utxos = try proto.utxoInfo.compactMap { try UtxoInfo(proto: $0) }
        self.memo = proto.memo
        self.vaultPubKeyECDSA = proto.vaultPublicKeyEcdsa
        self.vaultLocalPartyID = proto.vaultLocalPartyID
        self.swapPayload = try proto.swapPayload.map { try SwapPayload(proto: $0, vault: vault) }
        self.approvePayload = proto.hasErc20ApprovePayload ? ERC20ApprovePayload(proto: proto.erc20ApprovePayload) : nil
    }
    
    func mapToProtobuff() -> VSKeysignPayload {
        return .with {
            $0.coin = ProtoCoinResolver.proto(from: coin)
            $0.toAddress = toAddress
            $0.toAmount = String(toAmount)
            $0.blockchainSpecific = chainSpecific.mapToProtobuff()
            $0.utxoInfo = utxos.map { $0.mapToProtobuff() }
            $0.memo = memo ?? .empty
            $0.vaultPublicKeyEcdsa = vaultPubKeyECDSA
            $0.vaultLocalPartyID = vaultLocalPartyID
            $0.swapPayload = swapPayload?.mapToProtobuff()
            
            if let approvePayload {
                $0.erc20ApprovePayload = approvePayload.mapToProtobuff()
            }
        }
    }
}

extension ERC20ApprovePayload {
    
    init(proto: VSErc20ApprovePayload) {
        self.amount = BigInt(stringLiteral: proto.amount)
        self.spender = proto.spender
    }
    
    func mapToProtobuff() -> VSErc20ApprovePayload {
        return .with {
            $0.amount = String(amount)
            $0.spender = String(spender)
        }
    }
}

extension SwapPayload {
    
    init(proto: VSKeysignPayload.OneOf_SwapPayload, vault: Vault) throws {
        switch proto {
        case .thorchainSwapPayload(let value):
            self = .thorchain(THORChainSwapPayload(
                fromAddress: value.fromAddress,
                fromCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.toCoin),
                vaultAddress: value.vaultAddress,
                routerAddress: value.routerAddress.nilIfEmpty,
                fromAmount: BigInt(stringLiteral: value.fromAmount),
                toAmountDecimal: Decimal(string: value.toAmountDecimal) ?? 0,
                toAmountLimit: value.toAmountLimit,
                streamingInterval: value.streamingInterval,
                streamingQuantity: value.streamingQuantity,
                expirationTime: value.expirationTime,
                isAffiliate: value.isAffiliate
            ))
        case .mayachainSwapPayload(let value):
            self = .mayachain(THORChainSwapPayload(
                fromAddress: value.fromAddress,
                fromCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.toCoin),
                vaultAddress: value.vaultAddress,
                routerAddress: value.routerAddress.nilIfEmpty,
                fromAmount: BigInt(stringLiteral: value.fromAmount),
                toAmountDecimal: Decimal(string: value.toAmountDecimal) ?? 0,
                toAmountLimit: value.toAmountLimit,
                streamingInterval: value.streamingInterval,
                streamingQuantity: value.streamingQuantity,
                expirationTime: value.expirationTime,
                isAffiliate: value.isAffiliate
            ))
        case .oneinchSwapPayload(let value):
            self = .oneInch(OneInchSwapPayload(
                fromCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(vault: vault, coin: value.toCoin),
                fromAmount: BigInt(stringLiteral: value.fromAmount),
                toAmountDecimal: Decimal(string: value.toAmountDecimal) ?? 0,
                quote: OneInchQuote(
                    dstAmount: value.quote.dstAmount,
                    tx: OneInchQuote.Transaction(
                        from: value.quote.tx.from,
                        to: value.quote.tx.to,
                        data: value.quote.tx.data,
                        value: value.quote.tx.value,
                        gasPrice: value.quote.tx.gasPrice,
                        gas: value.quote.tx.gas
                    )
                )
            ))
        }
    }
    
    func mapToProtobuff() -> VSKeysignPayload.OneOf_SwapPayload {
        switch self {
        case .thorchain(let payload):
            return .thorchainSwapPayload(.with {
                $0.fromAddress = payload.fromAddress
                $0.fromCoin = ProtoCoinResolver.proto(from: payload.fromCoin)
                $0.toCoin = ProtoCoinResolver.proto(from: payload.toCoin)
                $0.vaultAddress = payload.vaultAddress
                $0.routerAddress = payload.routerAddress ?? .empty
                $0.fromAmount = String(payload.fromAmount)
                $0.toAmountDecimal = payload.toAmountDecimal.description
                $0.toAmountLimit = payload.toAmountLimit
                $0.streamingInterval = payload.streamingInterval
                $0.streamingQuantity = payload.streamingQuantity
                $0.expirationTime = payload.expirationTime
                $0.isAffiliate = payload.isAffiliate
            })
        case .mayachain(let payload):
            return .mayachainSwapPayload(.with {
                $0.fromAddress = payload.fromAddress
                $0.fromCoin = ProtoCoinResolver.proto(from: payload.fromCoin)
                $0.toCoin = ProtoCoinResolver.proto(from: payload.toCoin)
                $0.vaultAddress = payload.vaultAddress
                $0.routerAddress = payload.routerAddress ?? .empty
                $0.fromAmount = String(payload.fromAmount)
                $0.toAmountDecimal = payload.toAmountDecimal.description
                $0.toAmountLimit = payload.toAmountLimit
                $0.streamingInterval = payload.streamingInterval
                $0.streamingQuantity = payload.streamingQuantity
                $0.expirationTime = payload.expirationTime
                $0.isAffiliate = payload.isAffiliate
            })
        case .oneInch(let payload):
            return .oneinchSwapPayload(.with {
                $0.fromCoin = ProtoCoinResolver.proto(from: payload.fromCoin)
                $0.toCoin = ProtoCoinResolver.proto(from: payload.toCoin)
                $0.fromAmount = String(payload.fromAmount)
                $0.toAmountDecimal = payload.toAmountDecimal.description
                $0.quote = .with {
                    $0.dstAmount = payload.quote.dstAmount
                    $0.tx = .with {
                        $0.from = payload.quote.tx.from
                        $0.to = payload.quote.tx.to
                        $0.data = payload.quote.tx.data
                        $0.value = payload.quote.tx.value
                        $0.gasPrice = payload.quote.tx.gasPrice
                        $0.gas = payload.quote.tx.gas
                    }
                }
            })
        }
    }
}

extension BlockChainSpecific {
    
    init(proto: VSKeysignPayload.OneOf_BlockchainSpecific) throws {
        switch proto {
        case .utxoSpecific(let value):
            self = .UTXO(
                byteFee: BigInt(stringLiteral: value.byteFee),
                sendMaxAmount: value.sendMaxAmount
            )
        case .ethereumSpecific(let value):
            self = .Ethereum(
                maxFeePerGasWei: BigInt(stringLiteral: value.maxFeePerGasWei),
                priorityFeeWei: BigInt(stringLiteral: value.priorityFee),
                nonce: value.nonce,
                gasLimit: BigInt(stringLiteral: value.gasLimit)
            )
        case .thorchainSpecific(let value):
            self = .THORChain(
                accountNumber: value.accountNumber,
                sequence: value.sequence,
                fee: value.fee
            )
        case .mayaSpecific(let value):
            self = .MayaChain(
                accountNumber: value.accountNumber,
                sequence: value.sequence
            )
        case .cosmosSpecific(let value):
            self = .Cosmos(
                accountNumber: value.accountNumber,
                sequence: value.sequence,
                gas: value.gas
            )
        case .solanaSpecific(let value):
            self = .Solana(
                recentBlockHash: value.recentBlockHash,
                priorityFee: BigInt(stringLiteral: value.priorityFee),
                fromAddressPubKey: value.fromTokenAssociatedAddress,
                toAddressPubKey: value.toTokenAssociatedAddress
            )
        case .polkadotSpecific(let value):
            self = .Polkadot(
                recentBlockHash: value.recentBlockHash,
                nonce: value.nonce,
                currentBlockNumber: BigInt(stringLiteral: value.currentBlockNumber),
                specVersion: value.specVersion,
                transactionVersion: value.transactionVersion,
                genesisHash: value.genesisHash
            )
        case .suicheSpecific(let value):
            self = .Sui(
                referenceGasPrice: BigInt(stringLiteral: value.referenceGasPrice),
                coins: value.coinKeyValuePairs.map { [$0.key: $0.value] }
            )
        }
    }
    
    func mapToProtobuff() -> VSKeysignPayload.OneOf_BlockchainSpecific {
        switch self {
        case .UTXO(let byteFee, let sendMaxAmount):
            return .utxoSpecific(.with {
                $0.byteFee = String(byteFee)
                $0.sendMaxAmount = sendMaxAmount
            })
        case .Ethereum(let maxFeePerGasWei, let priorityFeeWei, let nonce, let gasLimit):
            return .ethereumSpecific(.with {
                $0.maxFeePerGasWei = String(maxFeePerGasWei)
                $0.priorityFee = String(priorityFeeWei)
                $0.nonce = nonce
                $0.gasLimit = String(gasLimit)
            })
        case .THORChain(let accountNumber, let sequence, let fee):
            return .thorchainSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.fee = fee
            })
        case .MayaChain(let accountNumber, let sequence):
            return .mayaSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
            })
        case .Cosmos(let accountNumber, let sequence, let gas):
            return .cosmosSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.gas = gas
            })
        case .Solana(let recentBlockHash, let priorityFee, let fromTokenAssociatedAddress, let toTokenAssociatedAddress):
            return .solanaSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.priorityFee = String(priorityFee)
                $0.fromTokenAssociatedAddress = fromTokenAssociatedAddress ?? .empty
                $0.toTokenAssociatedAddress = toTokenAssociatedAddress ?? .empty
            })
        case .Sui(let referenceGasPrice, let coins):
            return .suicheSpecific(.with {
                $0.referenceGasPrice = String(referenceGasPrice)
                $0.coinKeyValuePairs = coins.compactMap { coin in
                    guard let key = coin.keys.first, let value = coin.values.first else {
                        return nil
                    }
                    return .with {
                        $0.key = key
                        $0.value = value
                    }}
            })
        case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion, let genesisHash):
            return .polkadotSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.nonce = nonce
                $0.currentBlockNumber = String(currentBlockNumber)
                $0.specVersion = specVersion
                $0.transactionVersion = transactionVersion
                $0.genesisHash = genesisHash
            })
        }
    }
}

extension UtxoInfo {
    
    init(proto: VSUtxoInfo) throws {
        self.amount = proto.amount
        self.hash = proto.hash
        self.index = proto.index
    }
    
    func mapToProtobuff() -> VSUtxoInfo {
        return .with {
            $0.amount = amount
            $0.hash = hash
            $0.index = index
        }
    }
}
