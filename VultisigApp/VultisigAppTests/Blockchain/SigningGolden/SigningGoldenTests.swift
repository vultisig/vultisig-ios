//
//  SigningGoldenTests.swift
//  VultisigAppTests
//
//  Golden-vector harness for the signing pipeline. FAILS if the signed byte
//  output (or the bytes-to-sign) of any representative transaction changes —
//  so the upcoming signing-critical refactors (fetchSpecific, the
//  KeysignViewModel dispatcher extraction, broadcast, and SwapPayloadBuilder)
//  can prove byte-parity against a committed reference.
//
//  What is pinned
//  --------------
//  For every vector (one send per chain-family + swaps per provider + a
//  THORChain deposit + an ERC20 approve+swap):
//    1. `getPreSignedImageHash(...)` — the exact bytes each co-signer hashes.
//    2. `getSignedTransaction(...)` — the raw tx / hash / detached signature
//       the broadcast layer submits.
//    3. Dispatcher routing — `KeysignViewModel.getSignedTransaction` (the S4
//       seam) must produce byte-identical output to the direct leaf helper,
//       proving the payload was routed to the expected leaf builder.
//
//  Deferred coverage (documented, not yet pinned as byte goldens)
//  --------------------------------------------------------------
//    - SwapKit non-EVM routes (PSBT / SUI / TRON / TON / Cardano prebuilt):
//      need real provider PSBT/CBOR fixtures for byte goldens. The top-level
//      `.swapkit` dispatch is exercised by the routing-contract table
//      (`SigningGoldenRoutingTests`); per-`txType` signer selection is deferred.
//    - Solana generic (Jupiter/SwapKit-Solana) swaps: need a valid base64
//      Solana wire tx to inject a blockhash into.
//    - Cardano: WalletCore derives its address from an EXTENDED (BIP32-Ed25519)
//      key, not the plain 32-byte test key this harness signs with, so a
//      realistic Cardano vector needs extended-key fixtures — deferred.
//    - MayaChain: WalletCore has no native `maya1` HRP derivation (it yields a
//      `thor1` address the Maya helper rejects); a Maya vector needs a
//      custom-HRP address fixture. Routing (native → MayaChainHelper; EVM-token
//      → THORChainSwaps) is still covered by the routing-contract table.
//    - Native Sui Pay / QBTC (ML-DSA) / Bittensor: out of scope for this pass.
//  These are additive — each is one more `SigningGoldenVector`.
//
//  Record mode: `RECORD_SIGNING_GOLDENS=1` — see `SigningGoldenStore`.
//

import BigInt
import Tss
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SigningGoldenTests: XCTestCase {

    // MARK: - Byte parity + record

    func testSigningGoldens() throws {
        let existing = try SigningGoldenStore.load()
        var computed: [String: SigningGolden] = [:]
        let recording = SigningGoldenStore.isRecording

        var seenNames = Set<String>()
        // Any per-vector failure that means `computed` is not a trustworthy full
        // set — derive threw, non-determinism, or empty output. A record run must
        // NEVER overwrite the committed goldens when this is non-zero, or a broken
        // run silently clobbers a good reference with a partial/invalid map.
        var invalidVectors = 0

        for vector in SigningGoldenFactory.all {
            if seenNames.contains(vector.name) {
                XCTFail("duplicate vector name \(vector.name)")
                invalidVectors += 1
                continue
            }
            seenNames.insert(vector.name)

            do {
                let golden = try derive(vector)

                // Determinism: re-derive and require identical bytes. Signing is
                // deterministic (RFC6979 / ed25519), so any drift here is a real
                // non-determinism bug in the pipeline.
                let golden2 = try derive(vector)
                guard golden == golden2 else {
                    XCTFail("\(vector.name): signing is not deterministic")
                    invalidVectors += 1
                    continue
                }
                guard !golden.rawTransaction.isEmpty else {
                    XCTFail("\(vector.name): empty signed transaction — signatures likely did not verify")
                    invalidVectors += 1
                    continue
                }

                computed[vector.name] = golden

                if !recording {
                    if let reference = existing[vector.name] {
                        XCTAssertEqual(
                            golden, reference,
                            "\(vector.name): signed bytes drifted from the committed golden. If intentional, re-record (RECORD_SIGNING_GOLDENS=1) and review the JSON diff."
                        )
                    } else {
                        XCTFail("\(vector.name): no committed golden. Record with RECORD_SIGNING_GOLDENS=1 (or promote SigningGoldenVectors.actual.json).")
                    }
                }
            } catch {
                XCTFail("\(vector.name): failed to derive signing golden: \(error)")
                invalidVectors += 1
            }
        }

        // Always emit the inspection artifact so regeneration never depends on
        // env-var propagation into the simulator.
        try? SigningGoldenStore.saveActual(computed)

        if recording {
            // Refuse to overwrite the committed reference from a run where any
            // vector failed to derive/validate — the recorded map would be
            // incomplete or wrong. Inspect SigningGoldenVectors.actual.json.
            guard invalidVectors == 0 else {
                XCTFail("record aborted: \(invalidVectors) vector(s) failed to derive/validate — committed goldens left untouched.")
                return
            }
            try SigningGoldenStore.save(computed)
            // A record run overwrites the reference and skips every comparison,
            // so it must NEVER report as a passing validation — skip it, so CI
            // (or an accidental env var) can't mistake a record run for a green
            // drift-detecting gate.
            throw XCTSkip("Recorded \(computed.count) signing goldens to \(SigningGoldenStore.goldenFileURL.lastPathComponent). Re-run WITHOUT RECORD_SIGNING_GOLDENS=1 to validate.")
        } else {
            // Guard against silent under-coverage: every committed golden must
            // still have a matching live vector.
            for name in existing.keys where !seenNames.contains(name) {
                XCTFail("committed golden '\(name)' has no live vector — remove it or restore the vector.")
            }
        }
    }

    // MARK: - Dispatcher routing parity (S4)

    /// Drives each payload through the REAL `KeysignViewModel.getSignedTransaction`
    /// dispatcher and asserts it produces byte-identical output to the direct
    /// leaf helper. Combined with `testSigningGoldens` (leaf == committed golden),
    /// this pins the end-to-end contract S4's extraction must preserve: for each
    /// payload type the dispatcher emits exactly the expected leaf's bytes. A
    /// stronger "which concrete function ran" spy would require instrumenting the
    /// production dispatcher — out of scope for a test-only change to this
    /// HIGH-security, TSS-adjacent code — and byte drift (the actual refactor
    /// risk) is already caught here and by the golden comparison.
    func testDispatcherRoutesToExpectedLeaf() throws {
        for vector in SigningGoldenFactory.all where vector.assertsDispatcherParity {
            do {
                let payload = try vector.makePayload()
                let hashes = try vector.imageHashes(payload)
                let signatures = try SigningGoldenSigner.signatures(forImageHashes: hashes, curve: vector.curve)

                let leaf = try vector.signedTransaction(payload, signatures)

                let viewModel = KeysignViewModel()
                viewModel.vault = makeVault()
                viewModel.signatures = signatures
                let dispatched = try viewModel.getSignedTransaction(keysignPayload: payload)

                XCTAssertEqual(
                    fingerprint(dispatched), fingerprint(leaf),
                    "\(vector.name): KeysignViewModel dispatcher output != direct \(vector.expectedLeaf) leaf — routing changed."
                )
            } catch {
                XCTFail("\(vector.name): dispatcher routing check failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func derive(_ vector: SigningGoldenVector) throws -> SigningGolden {
        let payload = try vector.makePayload()
        let hashes = try vector.imageHashes(payload)
        XCTAssertFalse(hashes.isEmpty, "\(vector.name): no pre-image hashes")
        let signatures = try SigningGoldenSigner.signatures(forImageHashes: hashes, curve: vector.curve)
        let signed = try vector.signedTransaction(payload, signatures)

        switch signed {
        case .regular(let result):
            return SigningGolden(
                imageHashes: hashes,
                rawTransaction: result.rawTransaction,
                transactionHash: result.transactionHash,
                signature: result.signature,
                approveRawTransaction: nil,
                approveTransactionHash: nil
            )
        case .regularWithApprove(let approve, let transaction):
            return SigningGolden(
                imageHashes: hashes,
                rawTransaction: transaction.rawTransaction,
                transactionHash: transaction.transactionHash,
                signature: transaction.signature,
                approveRawTransaction: approve.rawTransaction,
                approveTransactionHash: approve.transactionHash
            )
        }
    }

    /// Stable string fingerprint of a signed-transaction result for equality.
    private func fingerprint(_ type: SignedTransactionType) -> String {
        switch type {
        case .regular(let result):
            return "regular|\(result.rawTransaction)|\(result.transactionHash)|\(result.signature ?? "")"
        case .regularWithApprove(let approve, let transaction):
            return "approve|\(approve.rawTransaction)|\(approve.transactionHash)|tx|\(transaction.rawTransaction)|\(transaction.transactionHash)"
        }
    }

    private func makeVault() -> Vault {
        Vault(
            name: "SigningGoldenVault",
            signers: ["localPartyID"],
            pubKeyECDSA: SigningGoldenSigner.publicKeyHex(for: .secp256k1),
            pubKeyEdDSA: SigningGoldenSigner.publicKeyHex(for: .ed25519),
            keyshares: [],
            localPartyID: "localPartyID",
            hexChainCode: "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7",
            resharePrefix: nil,
            libType: .DKLS
        )
    }
}
