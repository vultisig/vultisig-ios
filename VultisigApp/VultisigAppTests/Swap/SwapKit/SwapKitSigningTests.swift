//
//  SwapKitSigningTests.swift
//  VultisigAppTests
//
//  Phase 4 consolidated-signing coverage: pre-signing digest computation
//  + PSBT decode coverage for the five non-EVM SwapKit source chains
//  (BTC, SUI, TRON, TON, ADA). MPC-driven signed-tx assembly isn't
//  exercised end-to-end here — that requires a live keysign session;
//  digests are pinnable and the assembly paths are covered by the
//  per-chain signer unit tests below where deterministic.
//
//  Decision log (TRON option choice):
//  --------------------------------
//  We sign SwapKit's `raw_data_hex` directly (option B in the consolidated
//  signing plan): the canonical Tron signing digest is
//  `sha256(raw_data_bytes)`, which also happens to equal SwapKit's
//  reported `txID`. The assertion below pins that equality and locks the
//  choice in place — if SwapKit ever ships a transaction whose `txID`
//  diverges from `sha256(raw_data_hex)`, the test fires.
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitSigningTests: XCTestCase {

    // MARK: - BTC PSBT decoder + signer

    func testBTCPSBTDecodesIntoSignBitcoinAllInputsOurs() throws {
        let response = try fixture(name: "v3-real-btc-all-swap")
        guard case let .psbt(base64) = response.tx else {
            return XCTFail("expected PSBT tx")
        }
        let psbtBytes = try XCTUnwrap(Data(base64Encoded: base64))
        let signBitcoin = try SwapKitBTCSigner.decodeToSignBitcoin(psbtBytes: psbtBytes)

        XCTAssertEqual(signBitcoin.version, 2)
        XCTAssertEqual(signBitcoin.locktime, 0)
        XCTAssertEqual(signBitcoin.inputs.count, 4)
        XCTAssertEqual(signBitcoin.outputs.count, 1)
        // SwapKit only puts the user's UTXOs in PSBT inputs, so every input
        // must be `is_ours = true` for the BIP-143 sighash + witness path
        // to fire on every input.
        for input in signBitcoin.inputs {
            XCTAssertTrue(input.isOurs, "every SwapKit BTC input is the user's")
            XCTAssertEqual(input.scriptType, "p2wpkh", "fixture inputs are P2WPKH")
            XCTAssertEqual(input.sequence, 0xFFFFFFFF)
        }
        // Output goes to SwapKit's deposit address.
        let output = try XCTUnwrap(signBitcoin.outputs.first)
        XCTAssertEqual(output.amount, 12_466)
        XCTAssertEqual(
            output.scriptPubKey,
            "00147baaaca44c91115ae35dce3410f7395522f1c1aa",
            "output script must encode `bc1q0w42efzvjyg44c6aec6ppaee2530rsd2036hrp`"
        )
    }

    func testBTCPSBTPreSigningHashesAreDeterministic() throws {
        let payload = try makeSwapKitPayload(
            fixture: "v3-real-btc-all-swap",
            txType: "PSBT",
            txPayloadBytes: { Data(base64Encoded: try $0.psbtBase64()) ?? Data() }
        )
        let hashes = try SwapKitBTCSigner.preSigningHashes(payload: payload)
        // 4 inputs × 1 sighash each. BIP-143 sighashes are deterministic per
        // PSBT + scriptPubKey + sighash_type. We pin the sorted hex set so
        // any change to the SignBitcoin transcoding (off-by-one varint,
        // amount endianness, scriptCode bytes) surfaces here.
        XCTAssertEqual(hashes.count, 4)
        XCTAssertEqual(hashes, hashes.sorted(), "preSigningHashes returns sorted hex")
        // Pin the actual SHA256d sighash bytes for the NEAR-routed BTC swap.
        // Computed against the fixture PSBT + the canonical BIP-143 preimage.
        XCTAssertEqual(hashes, [
            "3725e1553bb43700c74d97edd361ed8538416b106e7f968e43023ac3f2e1e404",
            "447a8a57d19fafa308c3ed817c76e4455b581c77d1b7eef03d85440100ba6b78",
            "73935a24a8dd1df3fb5b6018d7f6d5ad95b3774ea55cbda87f62b6b28ee0f8ba",
            "9a32077b87e4a99bf6942350eb88db33145a28cddb736fb3d2b736c89d7f92c7"
        ], "BIP-143 sighashes are pinnable — drift here is a regression")
    }

    func testBTCPSBTRejectsBadMagic() {
        // Truncate the magic. Must error before reaching the sighash path.
        let bad = SwapKitSwapPayload(
            fromCoin: makeBtcCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(500_000),
            toAmountDecimal: 0,
            txType: "PSBT",
            txPayload: Data([0x70, 0x73, 0x62, 0x00, 0xff, 0x00]),
            targetAddress: "bc1qtest",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitBTCSigner.preSigningHashes(payload: bad)) { err in
            guard let typed = err as? SwapKitBTCSignerError else {
                return XCTFail("expected SwapKitBTCSignerError, got \(err)")
            }
            switch typed {
            case .invalidMagic: break
            default: XCTFail("expected .invalidMagic, got \(typed)")
            }
        }
    }

    // MARK: - SUI Blake2b digest

    func testSuiDigestPrependsIntentPrefix() throws {
        let response = try fixture(name: "v3-sui-swap-fresh")
        guard case let .sui(base64) = response.tx else { return XCTFail("expected sui tx") }
        let ptb = try XCTUnwrap(Data(base64Encoded: base64))
        let payload = SwapKitSwapPayload(
            fromCoin: makeSuiCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(10_000_000_000),
            toAmountDecimal: Decimal(string: "39.5") ?? 0,
            txType: "SUI",
            txPayload: ptb,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
        let digest = try SwapKitSuiSigner.digest(payload: payload)
        // Blake2b-32 of (intent_prefix [0x00,0x00,0x00] || ptb_bytes).
        XCTAssertEqual(digest.count, 32, "Sui digest is Blake2b-32")
        // Pinned digest for the captured fixture. If SwapKit ever changes
        // the PTB shape, or our intent-prefix bytes drift, this fires.
        XCTAssertEqual(
            digest.hexString,
            "3a7a34f5ba5544996fc24d400cace979c5ecef4bde532e563caf210ea1de5d57",
            "Sui Blake2b-32 digest is pinnable from the SwapKit PTB"
        )
    }

    func testSuiDigestRejectsEmptyPTB() {
        let empty = SwapKitSwapPayload(
            fromCoin: makeSuiCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: 0,
            toAmountDecimal: 0,
            txType: "SUI",
            txPayload: Data(),
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitSuiSigner.digest(payload: empty))
    }

    func testSuiPreSigningHashIsSingleEntry() throws {
        let payload = try makeSuiPayload()
        let hashes = try SwapKitSuiSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1, "Sui transactions sign a single Blake2b-32 digest")
    }

    // MARK: - TRON sha256 digest

    func testTronDigestEqualsSha256OfRawDataHex() throws {
        let response = try fixture(name: "v3-tron-final-swap-fresh")
        guard case let .tron(tron) = response.tx else { return XCTFail("expected tron tx") }
        let payload = try makeTronPayload(from: response, tronTx: tron)
        let digest = try SwapKitTronSigner.digest(payload: payload)
        XCTAssertEqual(digest.count, 32)
        // Tron's `txID` IS sha256(raw_data_bytes). SwapKit reports both, so
        // we pin the equality — if our digest derivation drifts, we'd
        // produce signatures the chain rejects.
        XCTAssertEqual(
            digest.hexString,
            tron.txID,
            "Tron signing digest must equal sha256(raw_data_bytes) (== txID)"
        )
    }

    func testTronPreSigningHashesIsSingleEntry() throws {
        let response = try fixture(name: "v3-tron-final-swap-fresh")
        guard case let .tron(tron) = response.tx else { return XCTFail("expected tron tx") }
        let payload = try makeTronPayload(from: response, tronTx: tron)
        let hashes = try SwapKitTronSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0], tron.txID)
    }

    func testTronRejectsMalformedJSON() {
        let bad = SwapKitSwapPayload(
            fromCoin: makeTronCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(50_000_000),
            toAmountDecimal: 0,
            txType: "TRON",
            txPayload: Data("not-json".utf8),
            targetAddress: "TUh93RjWWSxikbHA2U31pnYJYaP3zL45z5",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitTronSigner.digest(payload: bad))
    }

    func testTronRejectsMissingRawDataHex() throws {
        let object: [String: Any] = [
            "txID": "abcd",
            "raw_data": ["fee_limit": 10_000_000]
            // raw_data_hex intentionally absent
        ]
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let payload = SwapKitSwapPayload(
            fromCoin: makeTronCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: 0,
            toAmountDecimal: 0,
            txType: "TRON",
            txPayload: bytes,
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitTronSigner.digest(payload: payload)) { err in
            guard case SwapKitTronSignerError.missingRawDataHex = err else {
                return XCTFail("expected missingRawDataHex, got \(err)")
            }
        }
    }

    // MARK: - TON fall-through wiring

    func testTonPayloadFallsThroughToTonHelper() throws {
        // Phase 3 sets `keysignPayload.toAddress = targetAddress` and
        // `keysignPayload.toAmount = tx[0].amount` via the outer
        // `buildTransfer` call, so the existing `TonHelper.getPreSignedImageHash`
        // path signs the deposit transfer directly. Lock that contract by
        // asserting the SwapKit TON payload's targetAddress matches the
        // inner `tx[0].address` — the keysign-message dispatcher then just
        // breaks through to the TON helper.
        let response = try fixture(name: "v3-real-ton-swap")
        guard case let .ton(transfers) = response.tx else {
            return XCTFail("expected ton tx")
        }
        XCTAssertEqual(transfers.first?.address, response.targetAddress)
        XCTAssertEqual(transfers.first?.amount, "5000000000",
                       "fixture sends 5 TON = 5,000,000,000 nano-TON")
    }

    // MARK: - ADA fall-through wiring

    func testCardanoPayloadFallsThroughToCardanoHelper() throws {
        // For ADA: deposit-only flow. Phase 3 builder routes through
        // `SwapPayload.swapkit` with `txType=CARDANO` + empty `tx_payload`.
        // The dispatcher breaks through to the existing Cardano send
        // helper — `keysignPayload.toAddress = targetAddress`,
        // `keysignPayload.toAmount = sellAmount`.
        let response = try fixture(name: "v3-real-ada-swap")
        guard case .cardano = response.tx else { return XCTFail("expected cardano tx") }
        XCTAssertFalse(response.targetAddress.isEmpty,
                       "deposit-only flow routes by targetAddress")
        XCTAssertEqual(response.inboundAddress, response.targetAddress,
                       "deposit-only flow: inboundAddress == targetAddress")
        XCTAssertEqual(response.sellAmount, "50",
                       "sellAmount carries the human-units transfer amount")
    }

    // MARK: - Helpers

    private func fixture(name: String) throws -> SwapKitSwapResponse {
        try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: name)
    }

    private func makeSwapKitPayload(
        fixture name: String,
        txType: String,
        txPayloadBytes: (SwapKitSwapResponse) throws -> Data
    ) throws -> SwapKitSwapPayload {
        let response = try fixture(name: name)
        let bytes = try txPayloadBytes(response)
        return SwapKitSwapPayload(
            fromCoin: makeBtcCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(500_000),
            toAmountDecimal: 0,
            txType: txType,
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeSuiPayload() throws -> SwapKitSwapPayload {
        let response = try fixture(name: "v3-sui-swap-fresh")
        guard case let .sui(base64) = response.tx else { throw NSError(domain: "test", code: 0) }
        let ptb = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeSuiCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(10_000_000_000),
            toAmountDecimal: 0,
            txType: "SUI",
            txPayload: ptb,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeTronPayload(
        from response: SwapKitSwapResponse,
        tronTx: SwapKitTronTx
    ) throws -> SwapKitSwapPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(tronTx)
        return SwapKitSwapPayload(
            fromCoin: makeTronCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(50_000_000),
            toAmountDecimal: 0,
            txType: "TRON",
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeBtcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: "bc1qmjuvpz37st8096zed05mzeqj8lw4ttsm07llvh", hexPublicKey: "")
    }
    private func makeSuiCoin() -> Coin {
        let meta = CoinMeta.make(chain: .sui, ticker: "SUI", decimals: 9, isNativeToken: true)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
    private func makeTronCoin() -> Coin {
        let meta = CoinMeta.make(chain: .tron, ticker: "TRX", decimals: 6, isNativeToken: true)
        return Coin(asset: meta, address: "TLBaRhANQoJFTqre9Nf1mjuwNWjCJeYqUL", hexPublicKey: "")
    }
    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}

private extension SwapKitSwapResponse {
    func psbtBase64() throws -> String {
        guard case let .psbt(b64) = self.tx else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected psbt tx"])
        }
        return b64
    }
}
