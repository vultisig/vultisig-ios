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

extension KeysignPayload: ProtoMappable {

    enum Errors: Error {
        case blockchainSpecificNotFound
    }

    init(protobuf: VSKeysignPayload, vault: Vault) throws {
        guard let blockchainSpecific = protobuf.blockchainSpecific else {
            throw Errors.blockchainSpecificNotFound
        }

        self.toAddress = protobuf.toAddress
        self.toAmount = BigInt(stringLiteral: protobuf.toAmount)
        self.chainSpecific = try BlockChainSpecific(protobuf: blockchainSpecific)
        self.utxos = protobuf.utxoInfo.compactMap { try? UtxoInfo(protobuf: $0) }
        self.memo = protobuf.memo
        self.vaultPubKeyECDSA = protobuf.vaultPublicKeyEcdsa
        self.vaultLocalPartyID = protobuf.vaultLocalPartyID

        // TODO: Implement mapping for swapPayload & approvePayload
        self.swapPayload = nil
        self.approvePayload = nil

        self.coin = vault.coins.first(where: {
            $0.chain.name == protobuf.coin.chain &&
            $0.ticker == protobuf.coin.ticker
        })!
    }

    func mapToProtobuff() -> VSKeysignPayload {
        return .with {
            $0.toAddress = toAddress
            $0.toAmount = String(toAmount)
            $0.blockchainSpecific = chainSpecific.mapToProtobuff()
            $0.utxoInfo = utxos.map { $0.mapToProtobuff() }
            $0.memo = memo ?? .empty
            $0.vaultPublicKeyEcdsa = vaultPubKeyECDSA
            $0.vaultLocalPartyID = vaultLocalPartyID
            
            // TODO: Implement mapping for swapPayload & approvePayload
            $0.swapPayload = nil
            $0.erc20ApprovePayload = .with { _ in }
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
