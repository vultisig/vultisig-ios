//
//  TonExternalMessageEmulator.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-external-message-emulator")

/// Builds a wallet-v4R2 external-message BOC for emulation. Reuses the same
/// `TheOpenNetworkSigningInput` path that signing uses, then injects a 64-byte
/// zero placeholder signature so we get a structurally valid BOC without ever
/// running TSS. The emulation endpoint we target accepts unsigned BOCs via
/// `ignore_signature_check=true`, so the placeholder's invalid Ed25519 sig is
/// not a problem — the emulator only cares about message structure to surface
/// the actions a real broadcast would trigger.
///
/// Mirrors `createTonWalletV4ExternalMessageBoc` in the Vultisig Windows
/// codebase (`useTonSimulation.ts`).
enum TonExternalMessageEmulator {

    /// Build the unsigned external-message BOC for the supplied keysign payload
    /// (which must carry `signTon.tonMessages` from a TonConnect request).
    /// Returns `nil` on any structural failure rather than throwing — the
    /// caller falls back to the locally-decoded display.
    static func buildEmulationBoc(keysignPayload: KeysignPayload) -> String? {
        do {
            let inputData = try TonHelper.getPreSignedInputData(keysignPayload: keysignPayload)

            guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
                return nil
            }

            // 64-byte zero signature placeholder. WalletCore's TON compiler
            // wraps the signature into the canonical external-message BOC
            // without verifying it; emulation downstream uses
            // `ignore_signature_check=true`, so the actual bytes don't matter.
            let placeholderSignature = Data(count: 64)
            let signatures = DataVector()
            signatures.add(data: placeholderSignature)
            let publicKeys = DataVector()
            publicKeys.add(data: pubKeyData)

            let compiled = TransactionCompiler.compileWithSignatures(
                coinType: .ton,
                txInputData: inputData,
                signatures: signatures,
                publicKeys: publicKeys
            )

            let output = try TheOpenNetworkSigningOutput(serializedBytes: compiled)
            if !output.errorMessage.isEmpty {
                logger.error("TON compiler error: \(output.errorMessage, privacy: .public)")
                return nil
            }

            // `output.encoded` is already the base64-encoded BOC string per
            // WalletCore's TON output schema — pass through unchanged.
            let encoded = output.encoded
            guard !encoded.isEmpty else { return nil }
            return encoded
        } catch {
            logger.error("buildEmulationBoc failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
