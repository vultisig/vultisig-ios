//
//  SuiHelperInputDataTests.swift
//  VultisigApp
//
//  Pins the WalletCore `Sui.SigningInput` that `SuiHelper.getPreSignedInputData`
//  builds for the two native flows:
//
//  * Native SUI send (`PaySui`): only the largest objects needed to fund
//    amount + gas are referenced (covering selection), so a balance scattered
//    across many objects is merged — WalletCore/Sui gas-smashes the selected set
//    into one `GasCoin` — without referencing every object and overflowing Sui's
//    128 KiB / 256-gas-object transaction limits.
//
//  * Token send (`Pay`): the token's objects are covering-selected as inputs and
//    a *single* SUI object pays gas. That object is selected to cover the gas
//    budget (smallest covering object), not taken arbitrarily, so the send
//    doesn't fail when the first object the RPC returned is too small.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SuiHelperInputDataTests: XCTestCase {

    private let nativeType = "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"
    private let tokenType = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"
    private let recipient = "0x51d5b8e2f3d2f0aef0aefdc4e6c0f4f3d2b1a09788c7e6f5d4c3b2a190817263"

    // MARK: - Fixtures

    private func makeCoin(isNative: Bool) -> Coin {
        let key = PrivateKey()
        let publicKey = key.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .sui,
            ticker: isNative ? "SUI" : "COIN",
            logo: "sui",
            decimals: isNative ? 9 : 8,
            priceProviderId: "sui",
            contractAddress: isNative ? "" : tokenType,
            isNativeToken: isNative
        )
        return Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .sui).description,
            hexPublicKey: publicKey.data.hexString
        )
    }

    private func coinObject(_ id: String, type: String, balance: String, version: String = "1") -> [String: String] {
        [
            "objectID": id,
            "version": version,
            "objectDigest": "digest-\(id)",
            "balance": balance,
            "coinType": type
        ]
    }

    private func makePayload(coin: Coin, coins: [[String: String]], amount: BigInt, gasBudget: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: recipient,
            toAmount: amount,
            chainSpecific: .Sui(referenceGasPrice: BigInt(1000), coins: coins, gasBudget: gasBudget),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
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

    // MARK: - Native send merges the objects it needs

    /// A native SUI send whose balance is scattered across three objects
    /// references the largest objects that cover amount + gas as
    /// `PaySui.inputCoins` — WalletCore gas-smashes them into one spendable
    /// `GasCoin`, so the send is not capped at a single object's balance.
    func testNativeSendSelectsLargestObjectsCoveringAmountPlusGas() throws {
        let coin = makeCoin(isNative: true)
        let coins = [
            coinObject("0xa", type: nativeType, balance: "1000000000"),
            coinObject("0xb", type: nativeType, balance: "2000000000"),
            coinObject("0xc", type: nativeType, balance: "3000000000")
        ]
        // Amount larger than any single object: the two largest (3 + 2) cover
        // amount + gas, so they are merged and the smallest object is left out.
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(4_000_000_000), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .paySui(let paySui) = input.transactionPayload else {
            return XCTFail("expected a PaySui payload for a native SUI send")
        }
        XCTAssertEqual(Set(paySui.inputCoins.map { $0.objectID }), ["0xc", "0xb"])
        XCTAssertEqual(paySui.amounts, [4_000_000_000])
    }

    /// A small native send needs only the single largest object — the transaction
    /// stays minimal instead of referencing every object the wallet holds.
    func testNativeSmallSendSelectsOnlyLargestObject() throws {
        let coin = makeCoin(isNative: true)
        let coins = [
            coinObject("0xa", type: nativeType, balance: "1000000000"),
            coinObject("0xb", type: nativeType, balance: "2000000000"),
            coinObject("0xc", type: nativeType, balance: "3000000000")
        ]
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(100_000_000), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .paySui(let paySui) = input.transactionPayload else {
            return XCTFail("expected a PaySui payload")
        }
        XCTAssertEqual(paySui.inputCoins.map { $0.objectID }, ["0xc"])
    }

    /// When the amount approaches the full balance, every object is needed to
    /// cover amount + gas and all are merged.
    func testNativeNearMaxSendSelectsAllObjects() throws {
        let coin = makeCoin(isNative: true)
        let coins = [
            coinObject("0xa", type: nativeType, balance: "1000000000"),
            coinObject("0xb", type: nativeType, balance: "2000000000"),
            coinObject("0xc", type: nativeType, balance: "3000000000")
        ]
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(5_900_000_000), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .paySui(let paySui) = input.transactionPayload else {
            return XCTFail("expected a PaySui payload")
        }
        XCTAssertEqual(Set(paySui.inputCoins.map { $0.objectID }), ["0xa", "0xb", "0xc"])
    }

    /// A wallet whose balance is spread across many small objects references only
    /// the few largest objects needed — the fix for the "serialized transaction
    /// size exceeded maximum" broadcast failure.
    func testNativeDustyWalletReferencesOnlyNeededObjects() throws {
        let coin = makeCoin(isNative: true)
        var coins = [coinObject("0xbig", type: nativeType, balance: "10000000000")]
        // 800 dust objects the send should not need to reference.
        for i in 0..<800 {
            coins.append(coinObject("0xdust\(i)", type: nativeType, balance: "1000"))
        }
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(1_000_000_000), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .paySui(let paySui) = input.transactionPayload else {
            return XCTFail("expected a PaySui payload")
        }
        XCTAssertEqual(paySui.inputCoins.map { $0.objectID }, ["0xbig"])
        XCTAssertLessThanOrEqual(paySui.inputCoins.count, SuiConstants.maxInputCoinObjects)
    }

    /// Look-alike objects (LST / memecoin whose type merely contains "SUI") are
    /// never passed as native inputs.
    func testNativeSendExcludesLookAlikeObjects() throws {
        let coin = makeCoin(isNative: true)
        let coins = [
            coinObject("0xnative", type: nativeType, balance: "5000000000"),
            coinObject("0xlst", type: "0xb45f::xsui::XSUI", balance: "9000000000")
        ]
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(1_000_000_000), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .paySui(let paySui) = input.transactionPayload else {
            return XCTFail("expected a PaySui payload")
        }
        XCTAssertEqual(paySui.inputCoins.map { $0.objectID }, ["0xnative"])
    }

    // MARK: - Token send selects a covering gas object

    /// A token send uses the token's objects as inputs and picks the smallest
    /// native SUI object that covers the gas budget — not the first object,
    /// which here is too small to pay gas. The amount needs both token objects.
    func testTokenSendSelectsSmallestCoveringGasObject() throws {
        let coin = makeCoin(isNative: false)
        let coins = [
            // First SUI object is too small to pay gas — the old `.first` pick.
            coinObject("0xgasTooSmall", type: nativeType, balance: "500000"),
            coinObject("0xgasCovers", type: nativeType, balance: "3000000"),
            coinObject("0xgasBig", type: nativeType, balance: "9000000"),
            coinObject("0xtoken1", type: tokenType, balance: "100"),
            coinObject("0xtoken2", type: tokenType, balance: "200")
        ]
        // 250 needs both token objects (200 + 100).
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(250), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .pay(let pay) = input.transactionPayload else {
            return XCTFail("expected a Pay payload for a token send")
        }
        XCTAssertEqual(Set(pay.inputCoins.map { $0.objectID }), ["0xtoken1", "0xtoken2"])
        XCTAssertEqual(pay.gas.objectID, "0xgasCovers")
    }

    /// Token inputs are covering-selected too: when the amount needs every token
    /// object they are all merged in-PTB; the gas object stays separate.
    func testTokenSendSelectsCoveringTokenObjects() throws {
        let coin = makeCoin(isNative: false)
        let coins = [
            coinObject("0xgas", type: nativeType, balance: "5000000"),
            coinObject("0xt1", type: tokenType, balance: "100"),
            coinObject("0xt2", type: tokenType, balance: "200"),
            coinObject("0xt3", type: tokenType, balance: "300")
        ]
        // 550 needs all three token objects (300 + 200 + 100 = 600).
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(550), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .pay(let pay) = input.transactionPayload else {
            return XCTFail("expected a Pay payload")
        }
        XCTAssertEqual(Set(pay.inputCoins.map { $0.objectID }), ["0xt1", "0xt2", "0xt3"])
        XCTAssertEqual(pay.gas.objectID, "0xgas")
    }

    /// A token send that only needs the single largest token object references
    /// just that object — the gas object comes from the SUI objects.
    func testTokenSmallSendSelectsOnlyLargestTokenObject() throws {
        let coin = makeCoin(isNative: false)
        let coins = [
            coinObject("0xgas", type: nativeType, balance: "5000000"),
            coinObject("0xt1", type: tokenType, balance: "100"),
            coinObject("0xt2", type: tokenType, balance: "200"),
            coinObject("0xt3", type: tokenType, balance: "300")
        ]
        let payload = makePayload(coin: coin, coins: coins, amount: BigInt(250), gasBudget: BigInt(3_000_000))

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .pay(let pay) = input.transactionPayload else {
            return XCTFail("expected a Pay payload")
        }
        XCTAssertEqual(pay.inputCoins.map { $0.objectID }, ["0xt3"])
        XCTAssertEqual(pay.gas.objectID, "0xgas")
    }
}
