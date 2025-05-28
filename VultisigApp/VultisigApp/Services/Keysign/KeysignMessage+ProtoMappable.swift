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
    
    init(proto: VSKeysignMessage) throws {
        self.sessionID = proto.sessionID
        self.serviceName = proto.serviceName
        if proto.hasKeysignPayload {
            self.payload = try KeysignPayload(proto: proto.keysignPayload)
        } else {
            self.payload = nil
        }
        if proto.hasCustomMessagePayload {
            self.customMessagePayload = try CustomMessagePayload(proto: proto.customMessagePayload)
        } else {
            self.customMessagePayload = nil
        }
        self.encryptionKeyHex = proto.encryptionKeyHex
        self.useVultisigRelay = proto.useVultisigRelay
        self.payloadID =  proto.payloadID
    }
    
    func mapToProtobuff() -> VSKeysignMessage {
        return .with {
            $0.sessionID = sessionID
            $0.serviceName = serviceName
            if let payload {
                $0.keysignPayload = payload.mapToProtobuff()
            }
            if let customMessagePayload {
                $0.customMessagePayload = customMessagePayload.mapToProtobuff()
            }
            if !payloadID.isEmpty {
                $0.payloadID = payloadID
            }
            $0.encryptionKeyHex = encryptionKeyHex
            $0.useVultisigRelay = useVultisigRelay
        }
    }
}

extension CustomMessagePayload: ProtoMappable {
    
    init(proto: VSCustomMessagePayload) throws {
        self.method = proto.method
        self.message = proto.message
    }
    
    func mapToProtobuff() -> VSCustomMessagePayload {
        return VSCustomMessagePayload.with {
            $0.method = method
            $0.message = message
        }
    }
}

extension KeysignPayload: ProtoMappable {
    
    init(proto: VSKeysignPayload) throws {
        guard let blockchainSpecific = proto.blockchainSpecific else {
            throw ProtoMappableError.blockchainSpecificNotFound
        }
        
        self.coin = try ProtoCoinResolver.resolve(coin: proto.coin)
        self.toAddress = proto.toAddress
        self.toAmount = BigInt(stringLiteral: proto.toAmount)
        self.chainSpecific = try BlockChainSpecific(proto: blockchainSpecific)
        self.utxos = try proto.utxoInfo.compactMap { try UtxoInfo(proto: $0) }
        self.memo = proto.memo
        self.vaultPubKeyECDSA = proto.vaultPublicKeyEcdsa
        self.vaultLocalPartyID = proto.vaultLocalPartyID
        self.swapPayload = try proto.swapPayload.map { try SwapPayload(proto: $0) }
        self.approvePayload = proto.hasErc20ApprovePayload ? ERC20ApprovePayload(proto: proto.erc20ApprovePayload) : nil
        self.libType = proto.libType
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
            $0.libType = libType
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
    init(proto: VSKeysignPayload.OneOf_SwapPayload) throws {
        switch proto {
        case .thorchainSwapPayload(let value):
            self = .thorchain(THORChainSwapPayload(
                fromAddress: value.fromAddress,
                fromCoin: try ProtoCoinResolver.resolve(coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(coin: value.toCoin),
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
                fromCoin: try ProtoCoinResolver.resolve(coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(coin: value.toCoin),
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
                fromCoin: try ProtoCoinResolver.resolve(coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(coin: value.toCoin),
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
        case .eldorito(let payload):
            return .oneinchSwapPayload(.with {
                $0.fromCoin = ProtoCoinResolver.proto(from: payload.fromCoin)
                $0.toCoin = ProtoCoinResolver.proto(from: payload.toCoin)
                $0.fromAmount = String(payload.fromAmount)
                $0.toAmountDecimal = payload.toAmountDecimal.description
                $0.quote = .with {
                    $0.dstAmount = payload.toAmountDecimal.description
                    if let tx = payload.quote.tx {
                        $0.tx = .with {
                            $0.from = tx.from
                            $0.to = tx.to
                            $0.data = tx.data ?? ""
                            $0.value = tx.value
                            $0.gasPrice = tx.gasPrice ?? ""
                            $0.gas = tx.gas ?? .zero
                        }
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
                fee: value.fee,
                isDeposit: value.isDeposit
            )
        case .mayaSpecific(let value):
            self = .MayaChain(
                accountNumber: value.accountNumber,
                sequence: value.sequence,
                isDeposit: value.isDeposit
            )
        case .cosmosSpecific(let value):
            self = .Cosmos(
                accountNumber: value.accountNumber,
                sequence: value.sequence,
                gas: value.gas,
                transactionType: value.transactionType.rawValue,
                ibcDenomTrace: value.hasIbcDenomTraces ? CosmosIbcDenomTraceDenomTrace(path: value.ibcDenomTraces.path, baseDenom: value.ibcDenomTraces.baseDenom, height: value.ibcDenomTraces.latestBlock) : nil
            )
        case .solanaSpecific(let value):
            self = .Solana(
                recentBlockHash: value.recentBlockHash,
                priorityFee: BigInt(stringLiteral: value.priorityFee),
                fromAddressPubKey: value.fromTokenAssociatedAddress,
                toAddressPubKey: value.toTokenAssociatedAddress,
                hasProgramId: value.programID
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
            let coinsArray: [[String: String]] = value.coins.map { coin in
                return [
                    "objectID": coin.coinObjectID,
                    "version": coin.version,
                    "objectDigest": coin.digest,
                    "balance": coin.balance,
                    "coinType": coin.coinType
                ]
            }
            
            self = .Sui(
                referenceGasPrice: BigInt(stringLiteral: value.referenceGasPrice),
                coins: coinsArray
            )
        case .tonSpecific(let value):
            self = .Ton(
                sequenceNumber: value.sequenceNumber, expireAt: value.expireAt, bounceable: value.bounceable, sendMaxAmount: value.sendMaxAmount
            )
        case .rippleSpecific(let value):
            self = .Ripple(
                sequence: value.sequence,
                gas: value.gas,
                lastLedgerSequence: value.lastLedgerSequence
            )
        case .tronSpecific(let value):
            self = .Tron(
                timestamp: value.timestamp,
                expiration: value.expiration,
                blockHeaderTimestamp: value.blockHeaderTimestamp,
                blockHeaderNumber: value.blockHeaderNumber,
                blockHeaderVersion: value.blockHeaderVersion,
                blockHeaderTxTrieRoot: value.blockHeaderTxTrieRoot,
                blockHeaderParentHash: value.blockHeaderParentHash,
                blockHeaderWitnessAddress: value.blockHeaderWitnessAddress,
                gasFeeEstimation: value.gasEstimation
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
        case .THORChain(let accountNumber, let sequence, let fee, let isDeposit):
            return .thorchainSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.fee = fee
                $0.isDeposit = isDeposit
            })
        case .MayaChain(let accountNumber, let sequence, let isDeposit):
            return .mayaSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.isDeposit = isDeposit
            })
        case .Cosmos(let accountNumber, let sequence, let gas, let transactionType, let ibc):
            return .cosmosSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.gas = gas
                $0.transactionType = VSTransactionType(rawValue: transactionType) ?? .unspecified
                $0.ibcDenomTraces = VSCosmosIbcDenomTrace.with{
                    $0.baseDenom = ibc?.baseDenom ?? ""
                    $0.path = ibc?.path ?? ""
                    $0.latestBlock = ibc?.height ?? "0"
                }
            })
        case .Solana(let recentBlockHash, let priorityFee, let fromTokenAssociatedAddress, let toTokenAssociatedAddress, let tokenProgramId):
            return .solanaSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.priorityFee = String(priorityFee)
                $0.fromTokenAssociatedAddress = fromTokenAssociatedAddress ?? .empty
                $0.toTokenAssociatedAddress = toTokenAssociatedAddress ?? .empty
                $0.programID = tokenProgramId
            })
        case .Sui(let referenceGasPrice, let coins):
            // `coins` is of type `[[String: String]]`
            let suiCoins: [VSSuiCoin] = coins.map { coinDict in
                var suiCoin = VSSuiCoin()
                suiCoin.coinObjectID = coinDict["objectID"] ?? ""
                suiCoin.version = coinDict["version"] ?? ""
                suiCoin.digest = coinDict["objectDigest"] ?? ""
                suiCoin.balance = coinDict["balance"] ?? ""
                suiCoin.coinType = coinDict["coinType"] ?? ""
                return suiCoin
            }
            
            return .suicheSpecific(.with {
                $0.referenceGasPrice = String(referenceGasPrice)
                $0.coins = suiCoins
            })
            
        case .Ton(let sequenceNumber, let expireAt, let bounceable, let sendMaxAmount):
            return .tonSpecific(.with {
                $0.sequenceNumber = sequenceNumber
                $0.expireAt = expireAt
                $0.bounceable = bounceable
                $0.sendMaxAmount = sendMaxAmount
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
        case .Ripple(let sequence, let gas, let lastLedgerSequence):
            return .rippleSpecific(.with {
                $0.sequence = sequence
                $0.gas = gas
                $0.lastLedgerSequence = lastLedgerSequence
            })
            
        case .Tron(
            let timestamp,
            let expiration,
            let blockHeaderTimestamp,
            let blockHeaderNumber,
            let blockHeaderVersion,
            let blockHeaderTxTrieRoot,
            let blockHeaderParentHash,
            let blockHeaderWitnessAddress,
            let gasEstimation
        ):
            return .tronSpecific(.with {
                $0.timestamp = timestamp
                $0.expiration = expiration
                $0.blockHeaderTimestamp = blockHeaderTimestamp
                $0.blockHeaderNumber = blockHeaderNumber
                $0.blockHeaderVersion = blockHeaderVersion
                $0.blockHeaderParentHash = blockHeaderParentHash
                $0.blockHeaderTxTrieRoot = blockHeaderTxTrieRoot
                $0.blockHeaderWitnessAddress = blockHeaderWitnessAddress
                $0.gasEstimation = gasEstimation
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
