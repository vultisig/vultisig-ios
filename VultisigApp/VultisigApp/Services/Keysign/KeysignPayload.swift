//
//  KeysignPayload.swift
//  VultisigApp
//

import Foundation
import BigInt
import VultisigCommonData

struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String

    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }

    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false), utxos: [], memo: "Memo", swapPayload: nil, approvePayload: nil, vaultPubKeyECDSA: "12345", vaultLocalPartyID: "iPhone-100")
}

extension KeysignMessage: ProtoMappable {
    
    init(protobuf: VSKeysignMessage, vault: Vault) throws {
        self.sessionID = protobuf.sessionID
        self.serviceName = protobuf.serviceName
        self.payload = try KeysignPayload(protobuf: protobuf.keysignPayload, vault: vault)
        self.encryptionKeyHex = protobuf.encryptionKeyHex
        self.useVultisigRelay = protobuf.useVultisigRelay
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

    init(protobuf: VSKeysignPayload, vault: Vault) throws {
        guard let blockchainSpecific = protobuf.blockchainSpecific else {
            throw ProtoMappableError.blockchainSpecificNotFound
        }

        self.coin = try ProtoCoinResolver.resolve(vault: vault, coin: protobuf.coin)
        self.toAddress = protobuf.toAddress
        self.toAmount = BigInt(stringLiteral: protobuf.toAmount)
        self.chainSpecific = try BlockChainSpecific(protobuf: blockchainSpecific)
        self.utxos = try protobuf.utxoInfo.compactMap { try UtxoInfo(protobuf: $0) }
        self.memo = protobuf.memo
        self.vaultPubKeyECDSA = protobuf.vaultPublicKeyEcdsa
        self.vaultLocalPartyID = protobuf.vaultLocalPartyID
        self.swapPayload = try protobuf.swapPayload.map { try SwapPayload(protobuf: $0, vault: vault) }
        self.approvePayload = protobuf.hasErc20ApprovePayload ? ERC20ApprovePayload(protobuf: protobuf.erc20ApprovePayload) : nil
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
    
    init(protobuf: VSErc20ApprovePayload) {
        self.amount = BigInt(stringLiteral: protobuf.amount)
        self.spender = protobuf.spender
    }

    func mapToProtobuff() -> VSErc20ApprovePayload {
        return .with {
            $0.amount = String(amount)
            $0.spender = String(spender)
        }
    }
}

extension SwapPayload {

    init(protobuf: VSKeysignPayload.OneOf_SwapPayload, vault: Vault) throws {
        switch protobuf {
        case .thorchainSwapPayload(let value), .mayachainSwapPayload(let value):
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
        case .thorchain(let payload), .mayachain(let payload):
            return .thorchainSwapPayload(.with {
                $0.fromAddress = payload.fromAddress
                $0.fromCoin = ProtoCoinResolver.proto(from: payload.fromCoin)
                $0.toCoin = ProtoCoinResolver.proto(from: payload.toCoin)
                $0.vaultAddress = payload.vaultAddress
                $0.routerAddress = payload.routerAddress ?? .empty
                $0.fromAmount = payload.fromAddress
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

    init(protobuf: VSKeysignPayload.OneOf_BlockchainSpecific) throws {
        switch protobuf {
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
                priorityFee: BigInt(stringLiteral: value.priorityFee)
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
                $0.sequence = $0.sequence
                $0.fee = $0.fee
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
        case .Solana(let recentBlockHash, let priorityFee):
            return .solanaSpecific(.with {
                $0.recentBlockHash = recentBlockHash
                $0.priorityFee = String(priorityFee)
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

    init(protobuf: VSUtxoInfo) throws {
        self.amount = protobuf.amount
        self.hash = protobuf.hash
        self.index = protobuf.index
    }

    func mapToProtobuff() -> VSUtxoInfo {
        return .with {
            $0.amount = amount
            $0.hash = hash
            $0.index = index
        }
    }
}
