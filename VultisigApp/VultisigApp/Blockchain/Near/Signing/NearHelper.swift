//
//  NearHelper.swift
//  VultisigApp
//

import BigInt
import Foundation
import Tss
import WalletCore

/// Native NEAR transfer signing: the frozen payload values go into WalletCore's
/// `NEARSigningInput` unchanged, and every device signs the digest of the same
/// `TransactionV0` bytes.
///
/// Nothing here re-reads the chain. The nonce and block hash were frozen once by
/// the initiator (see `BlockChainService`) exactly because a co-signer cannot
/// recompute them without producing a different transaction, and the frozen
/// values are what the ceremony signs.
enum NearHelper {

    private static let depositBytes = 16
    private static let blockHashBytes = 32
    private static let ed25519PublicKeyBytes = 32
    private static let maxU128 = (BigInt(1) << 128) - 1

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        try signingInput(keysignPayload: keysignPayload).serializedData()
    }

    /// The transaction nonce an access-key nonce admits.
    ///
    /// nearcore's `verify_nonce` (mode `Monotonic`) rejects `tx_nonce <=
    /// ak_nonce` (`runtime/runtime/src/verifier.rs`), so the successor is the
    /// only valid choice — signing the access-key nonce itself produces a
    /// transaction every node refuses. The largest uint64 has no successor in
    /// the field, so that case fails closed instead of wrapping to zero (which
    /// would be accepted as a *stale* nonce by nothing and as a fresh one by an
    /// empty key — never what the user asked for).
    static func transactionNonce(accessKeyNonce: BigInt) throws -> UInt64 {
        guard let nonce = UInt64(exactly: accessKeyNonce + 1) else {
            throw HelperError.runtimeError(String(format: "nearErrorNonceOverflow".localized, accessKeyNonce.description))
        }
        return nonce
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        [try preSigningOutput(keysignPayload: keysignPayload).dataHash.hexString]
    }

    static func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let preSigningOutput = try Self.preSigningOutput(inputData: inputData)

        guard let publicKeyData = Data(hexString: keysignPayload.coin.hexPublicKey),
              let publicKey = PublicKey(data: publicKeyData, type: .ed25519) else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidPublicKey".localized, keysignPayload.coin.hexPublicKey))
        }

        // NEAR's Ed25519 message is `dataHash` (the sha256 digest), not `data`
        // (the Borsh body); every co-signer and the node sign and verify it.
        let signature = SignatureProvider(signatures: signatures).getSignature(preHash: preSigningOutput.dataHash)
        guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("nearErrorSignatureVerificationFailed".localized)
        }

        let allSignatures = DataVector()
        let publicKeys = DataVector()
        allSignatures.add(data: signature)
        publicKeys.add(data: publicKeyData)

        let compiled = TransactionCompiler.compileWithSignatures(
            coinType: .near,
            txInputData: inputData,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try NEARSigningOutput(serializedBytes: compiled)
        if !output.errorMessage.isEmpty {
            throw HelperError.runtimeError(output.errorMessage)
        }

        // The chain's id is the hash of the unsigned body, not of the signed
        // envelope (see `NearSignedTransaction`). It is what the broadcast is
        // matched against and what the status poll asks the node for.
        let transactionHash = try NearSignedTransaction.transactionHash(signedTransaction: output.signedTransaction)

        return SignedTransactionResult(
            rawTransaction: output.signedTransaction.base64EncodedString(),
            transactionHash: transactionHash
        )
    }

    /// The digest every device signs: `sha256(borsh(TransactionV0))`, hex.
    /// Asserted against an independently encoded body in the Near unit tests.
    private static func preSigningOutput(inputData: Data) throws -> TxCompilerPreSigningOutput {
        let hashes = TransactionCompiler.preImageHashes(coinType: .near, txInputData: inputData)
        let output = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !output.errorMessage.isEmpty {
            throw HelperError.runtimeError(output.errorMessage)
        }
        return output
    }

    private static func preSigningOutput(keysignPayload: KeysignPayload) throws -> TxCompilerPreSigningOutput {
        try preSigningOutput(inputData: try getPreSignedInputData(keysignPayload: keysignPayload))
    }

    /// A SwapKit deposit (NEAR Intents `simpleTransfer`) is signed as the plain
    /// transfer it describes, so the swap metadata must name exactly that
    /// transfer. Mirrors the SDK resolver's `assertSwapKitDepositOnly`.
    private static func assertSwapKitDepositOnly(_ keysignPayload: KeysignPayload) throws {
        guard let swapPayload = keysignPayload.swapPayload else { return }
        guard case .swapkit(let swap) = swapPayload else {
            throw HelperError.runtimeError("nearErrorSwapKitDepositOnly".localized)
        }
        guard swap.fromCoin.chain == .near, swap.fromCoin.isNativeToken else {
            throw HelperError.runtimeError("nearErrorSwapKitNotNativeNear".localized)
        }
        // NEAR Intents deposits go to a fresh per-swap implicit account; a named target is never one.
        guard NearAccountId.isImplicit(swap.targetAddress) else {
            throw HelperError.runtimeError(String(format: "nearErrorSwapKitDepositNotImplicit".localized, swap.targetAddress))
        }
        guard swap.targetAddress == keysignPayload.toAddress else {
            throw HelperError.runtimeError(
                String(format: "nearErrorSwapKitDepositReceiverMismatch".localized, swap.targetAddress, keysignPayload.toAddress)
            )
        }
        guard swap.fromAmount == keysignPayload.toAmount else {
            throw HelperError.runtimeError(String(
                format: "nearErrorSwapKitDepositAmountMismatch".localized,
                swap.fromAmount.description,
                keysignPayload.toAmount.description
            ))
        }
        guard swap.txPayload.isEmpty, swap.txType.isEmpty else {
            throw HelperError.runtimeError("nearErrorSwapKitDepositPrebuilt".localized)
        }
        guard swap.memo?.isEmpty ?? true else {
            throw HelperError.runtimeError("nearErrorSwapKitDepositMemo".localized)
        }
    }

    private static func signingInput(keysignPayload: KeysignPayload) throws -> NEARSigningInput {
        let coin = keysignPayload.coin
        try assertNativeTransferPayload(keysignPayload)
        let (nonce, blockHash) = try nearSigningFields(keysignPayload)

        guard let hexPublicKey = Data(hexString: coin.hexPublicKey), hexPublicKey.count == ed25519PublicKeyBytes else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidPublicKeyLength".localized, coin.hexPublicKey))
        }

        // The signer's own account is an implicit account: lowercase hex of the
        // selected Ed25519 key. Deriving it through WalletCore is what binds the
        // reviewed address to the key the ceremony signs with — a mismatch means
        // this device would sign a transaction funded by an account it does not
        // control.
        guard NearAccountId.isImplicit(coin.address) else {
            throw HelperError.runtimeError(String(format: "nearErrorSenderNotImplicit".localized, coin.address))
        }
        guard let publicKey = PublicKey(data: hexPublicKey, type: .ed25519) else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidPublicKey".localized, coin.hexPublicKey))
        }
        let derived = CoinType.near.deriveAddressFromPublicKey(publicKey: publicKey)
        guard derived == coin.address else {
            throw HelperError.runtimeError(
                String(format: "nearErrorSenderKeyMismatch".localized, coin.address, derived)
            )
        }

        return NEARSigningInput.with {
            $0.signerID = coin.address
            $0.nonce = nonce
            $0.receiverID = keysignPayload.toAddress
            $0.blockHash = blockHash
            $0.publicKey = hexPublicKey
            $0.actions = [
                NEARAction.with {
                    // Borsh `u128` deposit: 16 little-endian bytes, the encoding
                    // WalletCore emits into the transfer action.
                    $0.transfer = NEARTransfer.with { $0.deposit = depositBytes(for: keysignPayload.toAmount) }
                }
            ]
        }
    }

    /// The payload describes one native NEAR transfer and nothing else.
    private static func assertNativeTransferPayload(_ keysignPayload: KeysignPayload) throws {
        let coin = keysignPayload.coin
        guard coin.chain == .near, coin.isNativeToken else {
            throw HelperError.runtimeError("nearErrorTokensUnsupported".localized)
        }
        // A payload decoded from the wire carries `""` for an unset memo.
        guard keysignPayload.memo?.isEmpty ?? true else {
            throw HelperError.runtimeError("nearErrorMemo".localized)
        }
        try assertSwapKitDepositOnly(keysignPayload)
        guard keysignPayload.wasmExecuteContractPayload == nil,
              keysignPayload.tronTransferContractPayload == nil,
              keysignPayload.tronTriggerSmartContractPayload == nil,
              keysignPayload.tronTransferAssetContractPayload == nil else {
            throw HelperError.runtimeError("nearErrorContractPayload".localized)
        }
        guard keysignPayload.signData == nil else {
            throw HelperError.runtimeError("nearErrorCustomSignPayload".localized)
        }
        guard NearAccountId.isValid(keysignPayload.toAddress) else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidRecipient".localized, keysignPayload.toAddress))
        }
        guard keysignPayload.toAmount > 0, keysignPayload.toAmount <= maxU128 else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidAmount".localized, keysignPayload.toAmount.description))
        }
    }

    /// The frozen nonce and block hash, validated, from the payload's NEAR chain specific.
    private static func nearSigningFields(_ keysignPayload: KeysignPayload) throws -> (nonce: UInt64, blockHash: Data) {
        guard case let .Near(nonce, blockHash, gasFee, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("nearErrorMissingChainSpecific".localized)
        }

        // Display metadata, but a payload that cannot state its own reservation
        // is not a payload this signer should commit to.
        _ = try gasFeeInteger(gasFee, maximum: maxU128)

        guard blockHash.count == blockHashBytes else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidBlockHash".localized, blockHashBytes, blockHash.count))
        }
        guard nonce > 0 else {
            throw HelperError.runtimeError("nearErrorInvalidNonce".localized)
        }
        return (nonce, blockHash)
    }

    private static func depositBytes(for amount: BigInt) -> Data {
        var bytes = [UInt8](repeating: 0, count: depositBytes)
        // `serialize()` is the magnitude in big-endian order; Borsh wants
        // little-endian, so the bytes are reversed into a fixed 16-byte field.
        for (index, byte) in amount.serialize().reversed().enumerated() where index < depositBytes {
            bytes[index] = byte
        }
        return Data(bytes)
    }

    private static func gasFeeInteger(_ text: String, maximum: BigInt) throws -> BigInt {
        guard text.isUnsignedDecimal, let parsed = BigInt(text) else {
            throw HelperError.runtimeError(String(format: "nearErrorInvalidGasFee".localized, text))
        }
        guard parsed <= maximum else {
            throw HelperError.runtimeError(String(format: "nearErrorGasFeeTooLarge".localized, text))
        }
        return parsed
    }
}
