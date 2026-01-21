//
//  thorchain.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import VultisigCommonData

enum THORChainHelper {

    /// Validates and returns an AnyAddress for THORChain or Stagenet based on the chain type
    private static func validateThorchainAddress(_ address: String, chain: Chain) throws -> AnyAddress {
        if chain == .thorChainStagenet {
            guard let addr = AnyAddress(string: address, coin: .thorchain, hrp: "sthor") else {
                throw HelperError.runtimeError("\(address) is invalid stagenet address (expected sthor1...)")
            }
            return addr
        } else {
            guard let addr = AnyAddress(string: address, coin: .thorchain) else {
                throw HelperError.runtimeError("\(address) is invalid mainnet address (expected thor1...)")
            }
            return addr
        }
    }

    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .THORChain(let accountNumber, let sequence, _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number, sequence, or fee")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is missing")
        }

        let fromAddr = try validateThorchainAddress(keysignPayload.coin.address, chain: keysignPayload.coin.chain)

        var chainID = keysignPayload.coin.coinType.chainId
        let service = ThorchainServiceFactory.getService(for: keysignPayload.coin.chain)
        if chainID != service.network && !service.network.isEmpty {
            chainID = service.network
        }
        let input = try CosmosSigningInput.with {
            $0.chainID = chainID
            $0.publicKey = pubKeyData
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            $0.signingMode = CosmosSignDataBuilder.getSigningMode(keysignPayload: keysignPayload)
            $0.messages = [WalletCore.CosmosMessage.with {
                $0.thorchainDepositMessage = WalletCore.CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [TW_Cosmos_Proto_THORChainCoin.with {
                        $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                            $0.chain = "THOR"
                            $0.symbol = swapPayload.fromCoin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                            $0.ticker = swapPayload.fromCoin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
                            $0.synth = false
                            $0.secured = securedAssetsTickers.contains(swapPayload.fromCoin.ticker.uppercased())
                        }
                        $0.amount = String(swapPayload.fromAmount)
                        $0.decimals = Int64(swapPayload.fromCoin.decimals)
                    }]
                }
            }]
            $0.fee = try getFee(keysignPayload: keysignPayload)
        }

        return try input.serializedData()
    }

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        switch keysignPayload.coin.chain {
        case .thorChain, .thorChainStagenet:
            break
        default:
            throw HelperError.runtimeError("coin is not RUNE or RUNE Stagenet")
        }
        let fromAddr = try validateThorchainAddress(keysignPayload.coin.address, chain: keysignPayload.coin.chain)
        guard case .THORChain(let accountNumber, let sequence, _, let isDeposit, let transactionTypeRawValue) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number, sequence, or fee")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        let coin = CoinType.thorchain
        var chainID = coin.chainId
        let service = ThorchainServiceFactory.getService(for: keysignPayload.coin.chain)
        if chainID != service.network && !service.network.isEmpty {
            chainID = service.network
        }

        let transactionType = VSTransactionType(rawValue: transactionTypeRawValue) ?? .unspecified
        let messages: [WalletCore.CosmosMessage]
        var memo = keysignPayload.memo

        if let signDataMessagesResult = try CosmosSignDataBuilder.getMessages(keysignPayload: keysignPayload) {
            messages = signDataMessagesResult.messages
            memo = signDataMessagesResult.memo
        } else if isDeposit {
            // This should invoke the wasm contract for RUJI merge/unmerge
            if transactionType.isGenericWasmMessage {
                messages = [try WalletCore.CosmosMessage.with {
                    $0.wasmExecuteContractGeneric = try buildThorchainWasmGenericMessage(keysignPayload: keysignPayload, transactionType: transactionType)
                }]
            } else {
                messages = [buildThorchainDepositMessage(keysignPayload: keysignPayload, fromAddress: fromAddr)]
            }

        } else {
            if transactionType == .genericContract {
                messages = [try WalletCore.CosmosMessage.with {
                    $0.wasmExecuteContractGeneric =
                    try buildThorchainWasmGenericMessage(keysignPayload: keysignPayload, transactionType: transactionType)
                }]
            } else {
                messages = [try buildThorchainSendMessage(keysignPayload: keysignPayload, fromAddress: fromAddr)]
            }
        }

        let input = try CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = CosmosSignDataBuilder.getSigningMode(keysignPayload: keysignPayload)
            $0.chainID = chainID
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo {
                $0.memo = memo
            }
            $0.messages = messages
            $0.fee = try getFee(keysignPayload: keysignPayload)
        }
        return try input.serializedData()
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedTransaction
    }

    static func getSignedTransaction(
        coinHexPublicKey: String,
        inputData: Data,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }

            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .thorchain,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let transactionHash = CosmosSerializedParser.getTransactionHash(from: serializedData)
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash: transactionHash)
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed thorchain transaction,error:\(error.localizedDescription)")
        }
    }

    private static func buildThorchainWasmGenericMessage(keysignPayload: KeysignPayload, transactionType: VSTransactionType) throws -> WalletCore.CosmosMessage.WasmExecuteContractGeneric {
        let fromAddr = try validateThorchainAddress(keysignPayload.coin.address, chain: keysignPayload.coin.chain)

        let wasmGenericMessage = try WalletCore.CosmosMessage.WasmExecuteContractGeneric.with {
            $0.senderAddress = fromAddr.description
            $0.contractAddress = keysignPayload.toAddress
            switch transactionType {
            case .thorMerge:
                guard let memo = keysignPayload.memo?.lowercased() else {
                    throw HelperError.runtimeError("Missing memo for \(transactionType.rawValue)")
                }

                $0.executeMsg = """
                    { "deposit": {} }
                    """
                $0.coins = [
                    CosmosAmount.with {
                        $0.denom = memo.replacingOccurrences(of: "merge:", with: "")
                        $0.amount = String(keysignPayload.toAmount)
                    }
                ]
            case .thorUnmerge:
                guard let memo = keysignPayload.memo?.lowercased() else {
                    throw HelperError.runtimeError("Missing memo for \(transactionType.rawValue)")
                }
                // Parse shares amount from memo format: "unmerge:token:shares"
                let memoComponents = memo.split(separator: ":")
                let sharesAmount = memoComponents.count == 3 ? String(memoComponents[2]) : "0"
                $0.executeMsg = """
                     { "withdraw": { "share_amount": "\(sharesAmount)" } }
                     """
            case .genericContract:
                guard let contractPayload = keysignPayload.wasmExecuteContractPayload else {
                    throw HelperError.runtimeError("Invalid empty WasmExecuteContractPayload")
                }

                let coins = contractPayload.coins.map { coin in
                    CosmosAmount.with {
                        $0.denom = coin.denom
                        $0.amount = coin.amount
                    }
                }
                $0.executeMsg = contractPayload.executeMsg
                $0.senderAddress = contractPayload.senderAddress
                $0.contractAddress = contractPayload.contractAddress
                $0.coins = coins
            default:
                throw HelperError.runtimeError("Invalid tx type for WasmGenericMessage: \(transactionType.rawValue)")
            }
        }

        return wasmGenericMessage
    }

    private static func buildThorchainDepositMessage(keysignPayload: KeysignPayload, fromAddress: AnyAddress) -> WalletCore.CosmosMessage {
        let symbol = getTicker(coin: keysignPayload.coin)
        let assetTicker = getTicker(coin: keysignPayload.coin)
        let chainName = getChainName(coin: keysignPayload.coin)
        let isSecured = isSecuredAsset(coin: keysignPayload.coin)

        let coin = CosmosTHORChainCoin.with {
            $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                $0.chain = chainName
                $0.symbol = symbol
                $0.ticker = assetTicker
                $0.synth = false
                $0.secured = isSecured
            }
            if keysignPayload.toAmount > 0 {
                $0.amount = String(keysignPayload.toAmount)
                $0.decimals = Int64(keysignPayload.coin.decimals)
            }
        }

        return WalletCore.CosmosMessage.with {
            $0.thorchainDepositMessage = WalletCore.CosmosMessage.THORChainDeposit.with {
                $0.signer = fromAddress.data
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
                $0.coins = [coin]
            }
        }
    }

    private static func buildThorchainSendMessage(keysignPayload: KeysignPayload, fromAddress: AnyAddress) throws -> WalletCore.CosmosMessage {
        let toAddress = try validateThorchainAddress(keysignPayload.toAddress, chain: keysignPayload.coin.chain)

        return WalletCore.CosmosMessage.with {
            $0.thorchainSendMessage = WalletCore.CosmosMessage.THORChainSend.with {
                $0.fromAddress = fromAddress.data
                $0.amounts = [CosmosAmount.with {
                    $0.denom = (keysignPayload.coin.isNativeToken ? keysignPayload.coin.ticker : keysignPayload.coin.contractAddress).lowercased()
                    $0.amount = String(keysignPayload.toAmount)
                }]
                $0.toAddress = toAddress.data
            }
        }
    }

    private static func getTicker(coin: Coin) -> String {
        coin.isNativeToken ? "RUNE" : getNotNativeTicker(coin: coin)
    }

    private static func getNotNativeTicker(coin: Coin) -> String {
        return coin.ticker.uppercased().replacingOccurrences(of: "X/", with: "")
    }

    /// Returns the list of secured asset tickers
    private static var securedAssetsTickers: [String] {
        return ["BTC", "ETH", "BCH", "LTC", "DOGE", "AVAX", "BNB"]
    }

    /// Checks if a coin is a secured asset
    private static func isSecuredAsset(coin: Coin) -> Bool {
        return securedAssetsTickers.contains(coin.ticker.uppercased()) && !coin.isNativeToken
    }

    /// Gets the appropriate chain name for a coin in THORChain context
    /// - For secured assets: returns the chain ticker (e.g., "BTC", "ETH", "DOGE")
    /// - For BNB secured assets: returns "BSC"
    /// - For non-secured assets: returns "THOR"
    private static func getChainName(coin: Coin) -> String {
        guard isSecuredAsset(coin: coin) else {
            return "THOR"
        }

        let ticker = coin.ticker.uppercased()

        // BNB uses BSC chain
        if ticker == "BNB" {
            return "BSC"
        }

        // For other secured assets, use the coin's ticker THOR-DOGE will return DOGE
        return ticker
    }

    static func getFee(keysignPayload: KeysignPayload) throws -> WalletCore.CosmosFee {
        if let signDataFee = try CosmosSignDataBuilder.getFee(keysignPayload: keysignPayload) {
            return signDataFee
        }

        return WalletCore.CosmosFee.with {
            $0.gas = 20_000_000
        }
    }
}

private extension VSTransactionType {
    var isGenericWasmMessage: Bool {
        isMergeOrUnMerge || self == .genericContract
    }

    var isMergeOrUnMerge: Bool {
        self == .thorMerge  || self == .thorUnmerge
    }
}
