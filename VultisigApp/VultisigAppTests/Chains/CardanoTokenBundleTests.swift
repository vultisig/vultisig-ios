//
//  CardanoTokenBundleTests.swift
//  VultisigApp
//

@testable import VultisigApp
import BigInt
import XCTest

final class CardanoTokenBundleTests: XCTestCase {

    private let policy = String(repeating: "a", count: 56)
    private let assetHex = "474553" // "GES"

    private func makeCoin(contractAddress: String) throws -> Coin {
        // Build a minimal Cardano Coin via CoinFactory using TokensStore.cardano.
        let pubKey = "feedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00d"
        let chainCode = String(repeating: "0", count: 64)
        let base = try CoinFactory.create(
            asset: TokensStore.Token.cardano,
            publicKeyECDSA: pubKey,
            publicKeyEdDSA: pubKey,
            hexChainCode: chainCode,
            isDerived: false
        )
        // Override contractAddress to make this CNT-bearing.
        base.contractAddress = contractAddress
        base.isNativeToken = contractAddress.isEmpty
        return base
    }

    private func makePayload(coin: Coin, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: coin.address,
            toAmount: toAmount,
            chainSpecific: .Cardano(byteFee: 180_000, sendMaxAmount: false, ttl: 1),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    func testReturnsNilWhenContractAddressEmpty() throws {
        let coin = try makeCoin(contractAddress: "")
        let payload = makePayload(coin: coin, toAmount: 1_000_000)
        let bundle = try CardanoHelper.makeTokenBundle(for: payload)
        XCTAssertNil(bundle)
    }

    func testPopulatesPolicyAndAssetName() throws {
        let coin = try makeCoin(contractAddress: "\(policy).\(assetHex)")
        let payload = makePayload(coin: coin, toAmount: 42)
        let bundle = try XCTUnwrap(CardanoHelper.makeTokenBundle(for: payload))
        XCTAssertEqual(bundle.token.count, 1)
        let token = bundle.token[0]
        XCTAssertEqual(token.policyID, policy)
        XCTAssertEqual(token.assetNameHex, assetHex)
    }

    func testEncodesAmountAsMinimalBigEndian() throws {
        let coin = try makeCoin(contractAddress: "\(policy).\(assetHex)")
        let payload = makePayload(coin: coin, toAmount: 42)
        let bundle = try XCTUnwrap(CardanoHelper.makeTokenBundle(for: payload))
        XCTAssertEqual(bundle.token[0].amount, Data([0x2A]))
    }

    func testEncodesAmountCrossing256() throws {
        let coin = try makeCoin(contractAddress: "\(policy).\(assetHex)")
        let payload = makePayload(coin: coin, toAmount: 256)
        let bundle = try XCTUnwrap(CardanoHelper.makeTokenBundle(for: payload))
        XCTAssertEqual(bundle.token[0].amount, Data([0x01, 0x00]))
    }

    func testEncodesZeroAsSingleByte() throws {
        let coin = try makeCoin(contractAddress: "\(policy).\(assetHex)")
        let payload = makePayload(coin: coin, toAmount: 0)
        let bundle = try XCTUnwrap(CardanoHelper.makeTokenBundle(for: payload))
        XCTAssertEqual(bundle.token[0].amount, Data([0x00]))
    }

    func testEncodesLargeAmount() throws {
        // 18,446,744,073,709,551,616 = 2^64 — exceeds UInt64, must round-trip.
        let coin = try makeCoin(contractAddress: "\(policy).\(assetHex)")
        let big = BigInt("18446744073709551616") ?? .zero
        let payload = makePayload(coin: coin, toAmount: big)
        let bundle = try XCTUnwrap(CardanoHelper.makeTokenBundle(for: payload))
        XCTAssertEqual(bundle.token[0].amount, Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    func testRejectsInvalidAssetId() throws {
        let coin = try makeCoin(contractAddress: "not-an-asset-id")
        let payload = makePayload(coin: coin, toAmount: 1)
        XCTAssertThrowsError(try CardanoHelper.makeTokenBundle(for: payload)) { error in
            XCTAssertTrue(error is CardanoAssetIdError)
        }
    }
}
