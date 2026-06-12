//
//  SwapKitDogeTests.swift
//  VultisigAppTests
//
//  DOGE source via SwapKit NEAR-Intents: legacy P2PKH PSBT signed through
//  WalletCore's `CoinType.dogecoin` end-to-end. Same wire envelope as BTC
//  (`meta.txType: "PSBT"`) but the inner unsigned-tx body carries P2PKH
//  inputs that ride a frozen `BitcoinTransactionPlan` (no replanner — the
//  broadcast tx_id is load-bearing for NEAR Intents route tracking).
//
//  Real `/v3/swap` capture was blocked at probe time (the spike address
//  ran out of funds before the BCH fixture could land), so the test
//  fixture is a hand-crafted PSBT matching the byte-level shape the
//  DOGE plan documented: NON_WITNESS_UTXO (key `0x00`) with full embedded
//  prev-tx, 1 input + 2 outputs (deposit + change), legacy version 1.
//

import BigInt
import Foundation
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitDogeTests: XCTestCase {

    // MARK: - Decoder

    func testDogeSwapFixtureDecodesAsDogecoinPsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-doge-swap"
        )
        XCTAssertEqual(response.meta.txType, "PSBT")
        XCTAssertEqual(response.providers, ["NEAR"])
        XCTAssertEqual(response.subProvider, "NEAR")
        guard case let .dogecoinPsbt(base64) = response.tx else {
            return XCTFail("expected .dogecoinPsbt, got \(response.tx)")
        }
        XCTAssertTrue(base64.hasPrefix("cHNidP8B"),
                      "PSBT must start with `psbt\\xff` magic bytes")
        XCTAssertNotNil(Data(base64Encoded: base64), "tx must be valid base64")
        XCTAssertEqual(response.targetAddress, "D9DTLZMyferY6TVquM7GryViP7GtBntqWj")
        XCTAssertEqual(response.inboundAddress, response.targetAddress,
                       "NEAR routes: targetAddress == inboundAddress")
    }

    // MARK: - Payload builder

    func testDogePayloadBuilderProducesPSBTDogeTxType() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-doge-swap"
        )
        guard case let .dogecoinPsbt(base64) = response.tx else {
            return XCTFail("expected .dogecoinPsbt")
        }
        let payload = try SwapCryptoLogic.buildSwapKitLegacyPSBTPayload(
            fromCoin: makeDogeCoin(),
            toCoin: makeUsdcCoin(),
            fromAmountInCoin: BigInt(100_000_000_000), // 1000 DOGE in base units (8 decimals)
            toAmountDecimal: Decimal(string: "95.8") ?? 0,
            base64PSBT: base64,
            txType: "PSBT_DOGE",
            swapResponse: response
        )
        XCTAssertEqual(payload.txType, "PSBT_DOGE")
        XCTAssertEqual(payload.targetAddress, response.targetAddress)
        XCTAssertEqual(payload.txPayload.base64EncodedString(), base64,
                       "tx_payload bytes must round-trip back to the original PSBT")
        XCTAssertEqual(payload.subProvider, "NEAR")
    }

    // MARK: - Signer structural coverage

    func testDogeSignerProducesOneHashPerInput() throws {
        let payload = try makePayload()
        let hashes = try SwapKitDogeSigner.preSigningHashes(payload: payload)
        XCTAssertEqual(hashes.count, 1, "Fixture has 1 input → 1 preimage hash")
        for hash in hashes {
            XCTAssertEqual(hash.count, 64, "SHA256d preimage hashes are 32 bytes → 64 hex chars")
            XCTAssertEqual(hash, hash.lowercased(), "preSigningHashes returns lowercase hex")
        }
        XCTAssertEqual(hashes, hashes.sorted(), "preSigningHashes returns sorted hex")
    }

    func testDogeSignerBuildsBitcoinSigningInputWithFrozenPlan() throws {
        let payload = try makePayload()
        let input = try SwapKitDogeSigner.buildSigningInput(payload: payload)
        XCTAssertEqual(input.coinType, CoinType.dogecoin.rawValue)
        XCTAssertEqual(input.utxo.count, 1, "Fixture has 1 UTXO")
        // Frozen plan — replanner did NOT run, so plan.utxos matches the
        // PSBT's input set exactly.
        XCTAssertEqual(input.plan.utxos.count, 1, "Plan.utxos matches PSBT inputs")
        XCTAssertGreaterThan(input.plan.amount, 0, "Plan amount is the deposit output")
        XCTAssertGreaterThanOrEqual(input.plan.fee, 0, "Fee = sum(inputs) - sum(outputs) ≥ 0")
        XCTAssertEqual(
            input.plan.amount + input.plan.change + input.plan.fee,
            input.plan.availableAmount,
            "Frozen plan: amount + change + fee == availableAmount"
        )
        // P2PKH script keyed under the 20-byte hash160. SwapKitLegacyP2PKHSigner
        // extracts the hash from the scriptPubKey (`76 a9 14 <20> 88 ac`) and
        // stores the redeem script in `BitcoinSigningInput.scripts[hash.hex]`.
        XCTAssertEqual(input.scripts.count, 1, "One redeem-script entry per unique input hash")
    }

    func testDogeSignerDerivesToAddressFromPSBTOutputScriptNotTargetAddress() throws {
        // The DOGE spike fixture's `targetAddress`
        // (`D9DTLZMyferY6TVquM7GryViP7GtBntqWj`) does NOT match output 0's
        // P2PKH hash (`19fb7ab04f2de927ced3b8337ab45d5d046db6cf` =
        // `D7WUh91sP7W3adPvw8CcNM3KW6nbVsmeA7`). The signer must derive
        // `toAddress` from the parsed scriptPubKey, NOT from
        // `targetAddress`, otherwise the broadcast tx would route funds to
        // the wrong recipient. Regression pin for the output-script
        // preservation fix.
        let payload = try makePayload()
        let input = try SwapKitDogeSigner.buildSigningInput(payload: payload)
        XCTAssertEqual(
            input.toAddress, "D7WUh91sP7W3adPvw8CcNM3KW6nbVsmeA7",
            "toAddress must be derived from PSBT output 0's hash160 (not from SwapKit's targetAddress)"
        )
        XCTAssertEqual(
            input.changeAddress, "DP4TRTe5fHrCtWZbohniMNaJKXBT62JmJv",
            "changeAddress must be derived from PSBT output 1's hash160"
        )
    }

    func testDogeSignerRejectsEmptyPayload() {
        let empty = makeEmptyPayload()
        XCTAssertThrowsError(try SwapKitDogeSigner.preSigningHashes(payload: empty)) { err in
            guard case SwapKitDogeSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped SwapKitLegacyP2PKHSignerError, got \(err)")
            }
            guard case .missingPSBT = inner else {
                return XCTFail("expected .missingPSBT, got \(inner)")
            }
        }
    }

    func testDogeSignerRejectsBadMagic() {
        let bad = SwapKitSwapPayload(
            fromCoin: makeDogeCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(100),
            toAmountDecimal: 0,
            txType: "PSBT_DOGE",
            txPayload: Data([0x70, 0x73, 0x62, 0x00, 0xff, 0x00]),
            targetAddress: "D-test",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        XCTAssertThrowsError(try SwapKitDogeSigner.preSigningHashes(payload: bad)) { err in
            guard case SwapKitDogeSignerError.underlying(let inner) = err else {
                return XCTFail("expected wrapped error, got \(err)")
            }
            guard case .invalidMagic = inner else {
                return XCTFail("expected .invalidMagic, got \(inner)")
            }
        }
    }

    // MARK: - EVM builder defence-in-depth

    func testEvmBuilderRejectsDogePsbt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-doge-swap"
        )
        XCTAssertThrowsError(try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)) { err in
            guard case SwapKitError.unsupportedTxType(let txType) = err else {
                return XCTFail("expected unsupportedTxType, got \(err)")
            }
            XCTAssertEqual(txType, "PSBT_DOGE")
        }
    }

    // MARK: - Helpers

    private func makePayload() throws -> SwapKitSwapPayload {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-doge-swap"
        )
        guard case let .dogecoinPsbt(base64) = response.tx else {
            throw NSError(domain: "test", code: 0)
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        return SwapKitSwapPayload(
            fromCoin: makeDogeCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: BigInt(100_000_000_000),
            toAmountDecimal: 0,
            txType: "PSBT_DOGE",
            txPayload: bytes,
            targetAddress: response.targetAddress,
            inboundAddress: response.inboundAddress,
            memo: nil,
            subProvider: response.subProvider,
            swapID: response.swapId
        )
    }

    private func makeEmptyPayload() -> SwapKitSwapPayload {
        SwapKitSwapPayload(
            fromCoin: makeDogeCoin(),
            toCoin: makeUsdcCoin(),
            fromAmount: 0,
            toAmountDecimal: 0,
            txType: "PSBT_DOGE",
            txPayload: Data(),
            targetAddress: "",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
    }

    private func makeDogeCoin() -> Coin {
        let meta = CoinMeta.make(chain: .dogecoin, ticker: "DOGE", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L", hexPublicKey: "")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xtest", hexPublicKey: "")
    }
}
