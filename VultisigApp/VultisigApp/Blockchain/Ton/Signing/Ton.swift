//
//  Ton.Swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 20/10/24.
//

import Foundation
import OSLog
import Tss
import WalletCore
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-helper")

enum TonHelper {

    // The official Telegram Wallet chages a transaction fee of 0.05 TON. So we do it as well.
    static let defaultFee: BigInt = BigInt(50_000_000) // 0.05 TON
    static let defaultJettonFee: BigInt = BigInt(80_000_000) // 0.08 TON

    // TonConnect sendTransaction caps at 4 messages per request.
    static let maxTonConnectMessages = 4

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {

        guard keysignPayload.coin.chain.ticker == "TON" else {
            throw HelperError.runtimeError("coin is not TON")
        }

        guard case .Ton(let sequenceNumber, let expireAt, _, _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }

        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }

        let messages = try buildTransfers(keysignPayload: keysignPayload)

        let sequenceNumberUInt32 = UInt32(sequenceNumber.description) ?? 0
        let expireAtUInt32 = UInt32(expireAt.description) ?? 0

        let input = TheOpenNetworkSigningInput.with {
            $0.messages = messages
            $0.sequenceNumber = sequenceNumberUInt32
            $0.expireAt = expireAtUInt32
            $0.walletVersion = TheOpenNetworkWalletVersion.walletV4R2
            $0.publicKey = pubKeyData
        }

        let serializedData = try input.serializedData()

        return serializedData
    }

    private static func buildTransfers(keysignPayload: KeysignPayload) throws -> [TheOpenNetworkTransfer] {
        guard case .Ton(_, _, let bounceable, let sendMaxAmount, let jettonAddress, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ton chain specific")
        }

        // TonConnect sendTransaction: build one Transfer per tonMessage (up to 4),
        // threading stateInit and custom payloads through.
        if let signTon = keysignPayload.signTon {
            guard !signTon.tonMessages.isEmpty else {
                throw HelperError.runtimeError("tonMessages must not be empty")
            }
            guard signTon.tonMessages.count <= maxTonConnectMessages else {
                throw HelperError.runtimeError("TonConnect allows at most \(maxTonConnectMessages) messages, got \(signTon.tonMessages.count)")
            }
            return try signTon.tonMessages.map { try buildTonConnectTransfer(message: $0, bounceable: bounceable) }
        }

        // App-initiated TON send (native or jetton) — preserve existing single-transfer behavior.
        if !jettonAddress.isEmpty {
            return [try buildJettonTransfer(keysignPayload: keysignPayload, jettonAddress: jettonAddress)]
        }

        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("fail to get to address")
        }

        let baseMode = TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue
        var sendMode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | baseMode)
        if sendMaxAmount {
            sendMode = UInt32(TheOpenNetworkSendMode.attachAllContractBalance.rawValue | baseMode)
        }

        var hexAmount = keysignPayload.toAmount.toEvenLengthHexString()
        if sendMaxAmount {
            hexAmount = "0x00"
        }
        guard let amountData = Data(hexString: hexAmount) else {
            throw HelperError.runtimeError("invalid amount data")
        }

        let transfer = TheOpenNetworkTransfer.with {
            $0.dest = toAddress.description
            $0.amount = amountData
            $0.mode = sendMode

            if let memo = keysignPayload.memo {
                $0.comment = memo
            }
            $0.bounceable = bounceable
        }

        return [transfer]
    }

    private static func buildTonConnectTransfer(message: TonMessage, bounceable: Bool) throws -> TheOpenNetworkTransfer {
        guard let toAddress = AnyAddress(string: message.to, coin: .ton) else {
            throw HelperError.runtimeError("invalid TonConnect destination: \(message.to)")
        }

        guard let amountBig = BigInt(message.amount), amountBig > 0 else {
            throw HelperError.runtimeError("invalid TonConnect amount: \(message.amount)")
        }
        guard let amountData = Data(hexString: amountBig.toEvenLengthHexString()) else {
            throw HelperError.runtimeError("invalid TonConnect amount bytes")
        }

        let mode = UInt32(
            TheOpenNetworkSendMode.payFeesSeparately.rawValue |
            TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue
        )

        return TheOpenNetworkTransfer.with {
            $0.dest = toAddress.description
            $0.amount = amountData
            $0.mode = mode
            $0.bounceable = bounceable
            if let stateInit = message.stateInit, !stateInit.isEmpty {
                $0.stateInit = stateInit
            }
            if let payload = message.payload, !payload.isEmpty {
                $0.customPayload = payload
            }
        }
    }

    static func buildJettonTransfer(keysignPayload: KeysignPayload, jettonAddress: String) throws -> TheOpenNetworkTransfer {

        // Use canonical AnyAddress.description for all TON addresses to match WalletCore expectations
        guard let toAny = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            throw HelperError.runtimeError("Invalid TON to address: \(keysignPayload.toAddress)")
        }
        let destinationAddress = toAny.description

        guard !jettonAddress.isEmpty, let jettonAny = AnyAddress(string: jettonAddress, coin: .ton) else {
            throw HelperError.runtimeError("Jetton address cannot be empty or invalid: \(jettonAddress)")
        }
        let senderJettonWalletAddress = jettonAny.description

        guard let ownerAny = AnyAddress(string: keysignPayload.coin.address, coin: .ton) else {
            throw HelperError.runtimeError("Invalid TON owner address: \(keysignPayload.coin.address)")
        }

        // Attach 1 nanoton as forward amount (common jetton notify pattern)
        let forwardAmountMsg: BigInt = 1

        let amount = keysignPayload.toAmount.toEvenLengthHexString()
        logger.debug("hex amount: \(amount, privacy: .public)")
        guard let amountData = Data(hexString: amount) else {
            throw HelperError.runtimeError("Invalid amount data")
        }
        guard let forwardAmountMsgData = Data(hexString: forwardAmountMsg.toEvenLengthHexString()) else {
            throw HelperError.runtimeError("Invalid forward amount data")
        }
        let jettonTransfer = TheOpenNetworkJettonTransfer.with {
            $0.jettonAmount = amountData
            // Use owner's canonical address as response
            $0.responseAddress = ownerAny.description
            $0.toOwner = destinationAddress
            $0.forwardAmount = forwardAmountMsgData
        }

        let mode = UInt32(TheOpenNetworkSendMode.payFeesSeparately.rawValue | TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue)

        // Attach 0.08 TON for fees (matches Android/tests)
        let recommendedJettonsAmount = TonHelper.defaultJettonFee.toEvenLengthHexString()
        guard let recommendedJettonsAmountData = Data(hexString: recommendedJettonsAmount) else {
            throw HelperError.runtimeError("Invalid recommended jettons amount data")
        }
        let transfer = TheOpenNetworkTransfer.with {

            $0.amount = recommendedJettonsAmountData
            if let memo = keysignPayload.memo, !memo.isEmpty {
                $0.comment = memo
            }
            $0.bounceable = true // Jettons always bounceable
            $0.mode = mode
            $0.dest = senderJettonWalletAddress // Send to SENDER's jetton wallet, not master contract
            $0.jettonTransfer = jettonTransfer
        }

        return transfer
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            logger.error("preSigningOutput error: \(preSigningOutput.errorMessage, privacy: .public)")
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }

        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ton,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)

        let output = try TheOpenNetworkSigningOutput(serializedBytes: compileWithSignature)
        logger.info("Ton signed transaction output encoded: \(output.hash.hexString, privacy: .public)")
        let result = SignedTransactionResult(rawTransaction: output.encoded,
                                             transactionHash: output.hash.hexString)

        return result
    }
}
