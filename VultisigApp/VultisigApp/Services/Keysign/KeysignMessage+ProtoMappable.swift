//
//  KeysignMessage+ProtoMappable.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.07.2024.
//

import Foundation
import BigInt
import VultisigCommonData

enum KeysignPayloadFactoryError: Error {
    case invalidSwapProvider
}

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
        self.vaultLocalPartyID = proto.vaultLocalPartyID
        self.vaultPublicKeyECDSA = proto.vaultPublicKeyEcdsa
        self.chain = proto.chain
    }
    
    func mapToProtobuff() -> VSCustomMessagePayload {
        return VSCustomMessagePayload.with {
            $0.method = method
            $0.message = message
            $0.vaultLocalPartyID = vaultLocalPartyID
            $0.vaultPublicKeyEcdsa = vaultPublicKeyECDSA
            $0.chain = chain
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
        self.wasmExecuteContractPayload = try? WasmExecuteContractPayload(proto: proto.wasmExecuteContractPayload)
        self.skipBroadcast = proto.skipBroadcast
        self.signData = proto.signData.flatMap { SignData(proto: $0) }
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
            $0.wasmExecuteContractPayload = wasmExecuteContractPayload?.mapToProtobuff() ?? .init()
            $0.skipBroadcast = skipBroadcast
            $0.signData = signData?.mapToProtobuff()
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
            self = .generic(GenericSwapPayload(
                fromCoin: try ProtoCoinResolver.resolve(coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(coin: value.toCoin),
                fromAmount: BigInt(stringLiteral: value.fromAmount),
                toAmountDecimal: Decimal(string: value.toAmountDecimal) ?? 0,
                quote: EVMQuote(
                    dstAmount: value.quote.dstAmount,
                    tx: EVMQuote.Transaction(
                        from: value.quote.tx.from,
                        to: value.quote.tx.to,
                        data: value.quote.tx.data,
                        value: value.quote.tx.value,
                        gasPrice: value.quote.tx.gasPrice,
                        gas: value.quote.tx.gas
                    )
                ),
                provider: SwapProviderId(rawValue: value.provider) ?? .oneInch
            ))
        case .kyberswapSwapPayload(let value):
            self = .generic(GenericSwapPayload(
                fromCoin: try ProtoCoinResolver.resolve(coin: value.fromCoin),
                toCoin: try ProtoCoinResolver.resolve(coin: value.toCoin),
                fromAmount: BigInt(stringLiteral: value.fromAmount),
                toAmountDecimal: Decimal(string: value.toAmountDecimal) ?? 0,
                quote: EVMQuote(
                    dstAmount: value.quote.dstAmount,
                    tx: EVMQuote.Transaction(
                        from: value.quote.tx.from,
                        to: value.quote.tx.to,
                        data: value.quote.tx.data,
                        value: value.quote.tx.value,
                        gasPrice: value.quote.tx.gasPrice,
                        gas: value.quote.tx.gas
                    )
                ),
                provider: .kyberSwap
            ))
        }
    }
    
    func mapToProtobuff() -> VSKeysignPayload.OneOf_SwapPayload {
        switch self {
        case .thorchain(let payload), .thorchainStagenet(let payload):
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
        case .generic(let payload):
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
                $0.provider = payload.provider.rawValue
            })
        }
    }
}

extension BlockChainSpecific {
    
    init(proto: VSKeysignPayload.OneOf_BlockchainSpecific) throws {
        switch proto {
        case .utxoSpecific(let value):
            self = .UTXO(
                byteFee: value.byteFee.toBigInt(),
                sendMaxAmount: value.sendMaxAmount
            )
        case .cardano(let value):
            self = .Cardano(
                byteFee: BigInt(value.byteFee),
                sendMaxAmount: value.sendMaxAmount,
                ttl: value.ttl
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
                isDeposit: value.isDeposit,
                transactionType: value.transactionType.rawValue
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
                priorityLimit: value.hasComputeLimit ? BigInt(stringLiteral: value.computeLimit) : BigInt(0),
                fromAddressPubKey: value.fromTokenAssociatedAddress.isEmpty ? nil : value.fromTokenAssociatedAddress,
                toAddressPubKey: value.toTokenAssociatedAddress.isEmpty ? nil : value.toTokenAssociatedAddress,
                hasProgramId: value.programID
            )
        case .polkadotSpecific(let value):
            self = .Polkadot(
                recentBlockHash: value.recentBlockHash,
                nonce: value.nonce,
                currentBlockNumber: BigInt(stringLiteral: value.currentBlockNumber),
                specVersion: value.specVersion,
                transactionVersion: value.transactionVersion,
                genesisHash: value.genesisHash,
                gas: value.gas == 0 ? nil : BigInt(value.gas)
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
                coins: coinsArray,
                gasBudget: BigInt(stringLiteral: value.gasBudget)
            )
        case .tonSpecific(let value):
            self = .Ton(
                sequenceNumber: value.sequenceNumber,
                expireAt: value.expireAt,
                bounceable: value.bounceable,
                sendMaxAmount: value.sendMaxAmount,
                jettonAddress: value.jettonAddress,
                isActiveDestination: value.isActiveDestination
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
                $0.byteFee = byteFee.description
                $0.sendMaxAmount = sendMaxAmount
            })
        case .Cardano(let byteFee, let sendMaxAmount, let ttl):
            return .cardano(.with {
                $0.byteFee = Int64(byteFee)
                $0.sendMaxAmount = sendMaxAmount
                $0.ttl = ttl
            })
        case .Ethereum(let maxFeePerGasWei, let priorityFeeWei, let nonce, let gasLimit):
            return .ethereumSpecific(.with {
                $0.maxFeePerGasWei = String(maxFeePerGasWei)
                $0.priorityFee = String(priorityFeeWei)
                $0.nonce = nonce
                $0.gasLimit = String(gasLimit)
            })
        case .THORChain(let accountNumber, let sequence, let fee, let isDeposit, let transactionType):
            return .thorchainSpecific(.with {
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.fee = fee
                $0.isDeposit = isDeposit
                $0.transactionType = VSTransactionType(rawValue: transactionType) ?? .unspecified
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
        case .Solana(let recentBlockHash, let priorityFee, let priorityLimit, let fromTokenAssociatedAddress, let toTokenAssociatedAddress, let tokenProgramId):
            return .solanaSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.priorityFee = String(priorityFee)
                $0.computeLimit = String(priorityLimit)
                $0.fromTokenAssociatedAddress = fromTokenAssociatedAddress ?? .empty
                $0.toTokenAssociatedAddress = toTokenAssociatedAddress ?? .empty
                $0.programID = tokenProgramId
            })
        case .Sui(let referenceGasPrice, let coins, let gasBudget):
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
                $0.gasBudget = String(gasBudget)
                $0.coins = suiCoins
            })
            
        case .Ton(let sequenceNumber, let expireAt, let bounceable, let sendMaxAmount, let jettonAddress, let isActiveDestination):
            return .tonSpecific(.with {
                $0.sequenceNumber = sequenceNumber
                $0.expireAt = expireAt
                $0.bounceable = bounceable
                $0.sendMaxAmount = sendMaxAmount
                $0.jettonAddress = jettonAddress
                $0.isActiveDestination = isActiveDestination
            })
            
            
        case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion, let genesisHash, let gas):
            return .polkadotSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.nonce = nonce
                $0.currentBlockNumber = String(currentBlockNumber)
                $0.specVersion = specVersion
                $0.transactionVersion = transactionVersion
                $0.genesisHash = genesisHash
                $0.gas = UInt64(gas ?? 0)
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
