//
//  CosmosDappFeeFloorTests.swift
//  VultisigAppTests
//
//  The dApp-injected signing seam (the issue's "staking/signing" path). When a
//  dApp / WalletConnect / Keplr request carries its own fee, the SIGNED fee is
//  built by `CosmosSignDataBuilder.getFee` and the DISPLAYED fee comes from
//  `KeysignPayload.dappSuppliedCosmosFee()`. These tests pin that both apply
//  the Akash floor (so display == signed and neither is sub-floor), that
//  non-floored chains pass through verbatim, and that a peer-shared signDirect
//  request below the floor is REJECTED rather than silently rewritten (which
//  would diverge the cosigner hash).
//

@testable import VultisigApp
import WalletCore
import XCTest

final class CosmosDappFeeFloorTests: XCTestCase {

    // MARK: - Coin / payload builders

    private func makeCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "addr", hexPublicKey: "")
    }

    private func makePayload(coin: Coin, signData: SignData) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "",
            toAmount: 0,
            chainSpecific: .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signData
        )
    }

    private func aminoSignData(denom: String, amount: String, gas: String) -> SignData {
        let fee = CosmosFee(
            payer: "",
            granter: "",
            feePayer: "",
            amount: [CosmosCoin(amount: amount, denom: denom)],
            gas: gas
        )
        return .signAmino(SignAmino(fee: fee, msgs: []))
    }

    // MARK: - signAmino floor (Akash)

    func testAkashSignAminoSignedFeeIsFloored() throws {
        // Keplr-injected Akash staking fee: 7_500 uakt at 300k gas → 25_000.
        let coin = makeCoin(chain: .akash, ticker: "AKT", decimals: 6)
        let payload = makePayload(coin: coin, signData: aminoSignData(denom: "uakt", amount: "7500", gas: "300000"))

        let fee = try XCTUnwrap(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
        let uaktAmount = try XCTUnwrap(fee.amounts.first { $0.denom == "uakt" })
        XCTAssertEqual(uaktAmount.amount, "25000")
        XCTAssertEqual(fee.gas, 300_000)
    }

    func testAkashSignAminoDisplayFeeIsFloored() {
        // The displayed value (second device) must match the signed value.
        let coin = makeCoin(chain: .akash, ticker: "AKT", decimals: 6)
        let payload = makePayload(coin: coin, signData: aminoSignData(denom: "uakt", amount: "7500", gas: "300000"))

        XCTAssertEqual(payload.dappSuppliedCosmosFee(), 25_000)
    }

    func testAkashSignAminoAboveFloorPassesThrough() throws {
        let coin = makeCoin(chain: .akash, ticker: "AKT", decimals: 6)
        let payload = makePayload(coin: coin, signData: aminoSignData(denom: "uakt", amount: "40000", gas: "300000"))

        let fee = try XCTUnwrap(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
        let uaktAmount = try XCTUnwrap(fee.amounts.first { $0.denom == "uakt" })
        XCTAssertEqual(uaktAmount.amount, "40000")
        XCTAssertEqual(payload.dappSuppliedCosmosFee(), 40_000)
    }

    // MARK: - signAmino regression: non-floored chain unchanged

    func testGaiaSignAminoPassesThroughUnfloored() throws {
        let coin = makeCoin(chain: .gaiaChain, ticker: "UATOM", decimals: 6)
        let payload = makePayload(coin: coin, signData: aminoSignData(denom: "uatom", amount: "7500", gas: "200000"))

        let fee = try XCTUnwrap(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
        let uatomAmount = try XCTUnwrap(fee.amounts.first { $0.denom == "uatom" })
        XCTAssertEqual(uatomAmount.amount, "7500")
        XCTAssertEqual(payload.dappSuppliedCosmosFee(), 7_500)
    }

    // MARK: - signDirect: validate (reject), never rewrite peer-shared bytes

    func testAkashSignDirectSubFloorFeeIsRejected() {
        let coin = makeCoin(chain: .akash, ticker: "AKT", decimals: 6)
        let authInfoBytes = Self.encodeAuthInfo(denom: "uakt", amount: "7500", gasLimit: 300_000)
        let signDirect = SignDirect(
            bodyBytes: "",
            authInfoBytes: authInfoBytes,
            chainID: "akashnet-2",
            accountNumber: "0"
        )
        let payload = makePayload(coin: coin, signData: .signDirect(signDirect))

        XCTAssertThrowsError(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
    }

    func testAkashSignDirectAtFloorFeeIsAccepted() throws {
        let coin = makeCoin(chain: .akash, ticker: "AKT", decimals: 6)
        let authInfoBytes = Self.encodeAuthInfo(denom: "uakt", amount: "25000", gasLimit: 300_000)
        let signDirect = SignDirect(
            bodyBytes: "",
            authInfoBytes: authInfoBytes,
            chainID: "akashnet-2",
            accountNumber: "0"
        )
        let payload = makePayload(coin: coin, signData: .signDirect(signDirect))

        let fee = try XCTUnwrap(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
        let uaktAmount = try XCTUnwrap(fee.amounts.first { $0.denom == "uakt" })
        // The bytes are read verbatim (not rewritten) — they already meet the floor.
        XCTAssertEqual(uaktAmount.amount, "25000")
    }

    func testGaiaSignDirectSubFloorFeeIsAccepted() throws {
        // Non-floored chain: a low fee must NOT be rejected.
        let coin = makeCoin(chain: .gaiaChain, ticker: "UATOM", decimals: 6)
        let authInfoBytes = Self.encodeAuthInfo(denom: "uatom", amount: "1", gasLimit: 200_000)
        let signDirect = SignDirect(
            bodyBytes: "",
            authInfoBytes: authInfoBytes,
            chainID: "cosmoshub-4",
            accountNumber: "0"
        )
        let payload = makePayload(coin: coin, signData: .signDirect(signDirect))

        XCTAssertNoThrow(try CosmosSignDataBuilder.getFee(keysignPayload: payload))
    }

    // MARK: - Minimal protobuf encoder for AuthInfo { Fee { Coin, gas_limit } }

    /// Encodes a Cosmos `AuthInfo` carrying a single-coin `Fee`, matching the
    /// wire layout `CosmosSignDirectParser.extractFee` reads back:
    /// AuthInfo field 2 = Fee; Fee field 1 = repeated Coin, field 2 = gas_limit;
    /// Coin field 1 = denom (string), field 2 = amount (string).
    static func encodeAuthInfo(denom: String, amount: String, gasLimit: UInt64) -> String {
        let coin = lengthDelimited(field: 1, Array(denom.utf8))
            + lengthDelimited(field: 2, Array(amount.utf8))
        let fee = lengthDelimited(field: 1, coin)
            + varintField(field: 2, gasLimit)
        let authInfo = lengthDelimited(field: 2, fee)
        return Data(authInfo).base64EncodedString()
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while v != 0
        return bytes
    }

    private static func lengthDelimited(field: Int, _ payload: [UInt8]) -> [UInt8] {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(payload.count)) + payload
    }

    private static func varintField(field: Int, _ value: UInt64) -> [UInt8] {
        varint(UInt64(field << 3 | 0)) + varint(value)
    }
}
