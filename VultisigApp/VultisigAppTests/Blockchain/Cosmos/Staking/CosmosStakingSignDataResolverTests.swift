//
//  CosmosStakingSignDataResolverTests.swift
//  VultisigAppTests
//
//  Pins the Verify → KeysignPayload bridge for the Cosmos staking flow.
//
//  Two contracts under test:
//    1. Byte-equality — the resolver's `bodyBytes` for a single MsgDelegate
//       match the helper's `buildTxBodyMulti([encodeDelegate(...)], memo: "")`
//       output verbatim. This is the "memo-pin" guard against silent SDK
//       drift: if the helper changes its wire shape on a future bump, this
//       test fails loud.
//    2. Preflight gating — invalid validator addresses are rejected BEFORE
//       any SignDoc bytes get produced. The MPC ceremony never sees them.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingSignDataResolverTests: XCTestCase {

    // MARK: - Test fixtures

    /// Real checksum-valid `terravaloper1…` address — built once via the
    /// bech32 encoder so the preflight gate doesn't reject it.
    private static let validValidator = Bech32TestUtils.makeValoperAddress()

    private static func makeChainSpecific(accountNumber: UInt64 = 100, sequence: UInt64 = 42) -> BlockChainSpecific {
        .Cosmos(
            accountNumber: accountNumber,
            sequence: sequence,
            gas: 7_500,
            transactionType: 0,
            ibcDenomTrace: nil
        )
    }

    private static func makeTerraCoin() -> Coin {
        let meta = CoinMeta(
            chain: .terra,
            ticker: "LUNA",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna-2",
            contractAddress: "",
            isNativeToken: true
        )
        // 33-byte compressed secp256k1 pubkey (all 0x02) keeps the AuthInfo
        // bytes deterministic across runs.
        let pubKeyHex = "02" + String(repeating: "00", count: 32)
        return Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: pubKeyHex
        )
    }

    private static func makeSendTransaction(
        payload: CosmosStakingPayload,
        coin: Coin? = nil
    ) -> SendTransaction {
        let coin = coin ?? makeTerraCoin()
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: payload.validatorAddress ?? "",
            toAddressLabel: nil,
            amount: "0",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: true,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            cosmosStakingPayload: payload
        )
    }

    // MARK: - Byte-pin

    func testDelegateBodyBytesMatchHelperEncoderOutput() throws {
        let coin = Self.makeTerraCoin()
        let payload = CosmosStakingPayload.delegate(
            validator: Self.validValidator,
            denom: "uluna",
            amount: "1000000"
        )
        let tx = Self.makeSendTransaction(payload: payload, coin: coin)

        let signDirect = try CosmosStakingSignDataResolver.resolve(
            sendTransaction: tx,
            chainSpecific: Self.makeChainSpecific()
        )

        let expectedAny = CosmosStakingHelper.encodeDelegate(
            delegator: coin.address,
            validator: Self.validValidator,
            amount: "1000000",
            denom: "uluna"
        )
        let expectedBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [expectedAny], memo: "")
        XCTAssertEqual(
            signDirect.bodyBytes,
            expectedBody.base64EncodedString(),
            "Resolver body bytes must equal the helper encoder output for the same inputs"
        )
    }

    func testDelegateChainIdComesFromConfigEntry() throws {
        let payload = CosmosStakingPayload.delegate(
            validator: Self.validValidator,
            denom: "uluna",
            amount: "1000000"
        )
        let tx = Self.makeSendTransaction(payload: payload)

        let signDirect = try CosmosStakingSignDataResolver.resolve(
            sendTransaction: tx,
            chainSpecific: Self.makeChainSpecific()
        )
        XCTAssertEqual(signDirect.chainID, "phoenix-1")
    }

    func testAccountNumberFlowsFromChainSpecific() throws {
        let payload = CosmosStakingPayload.delegate(
            validator: Self.validValidator,
            denom: "uluna",
            amount: "1000000"
        )
        let tx = Self.makeSendTransaction(payload: payload)

        let signDirect = try CosmosStakingSignDataResolver.resolve(
            sendTransaction: tx,
            chainSpecific: Self.makeChainSpecific(accountNumber: 9_999, sequence: 11)
        )
        XCTAssertEqual(signDirect.accountNumber, "9999")
    }

    // MARK: - Multi-msg gas scaling (claim path)

    func testBatchClaimGasAndFeeScaleLinearlyWithValidatorCount() throws {
        let payload = CosmosStakingPayload.withdrawRewards(
            validators: [Self.validValidator, Self.validValidator, Self.validValidator],
            denom: "uluna"
        )
        let tx = Self.makeSendTransaction(payload: payload)

        let signDirect = try CosmosStakingSignDataResolver.resolve(
            sendTransaction: tx,
            chainSpecific: Self.makeChainSpecific()
        )
        // Recompute the expected AuthInfo with N=3 multiplier — the resolver
        // must produce the same bytes.
        let entry = try CosmosStakingConfig.entry(for: .terra)
        let pubKey = Data(hexString: tx.coin.hexPublicKey) ?? Data()
        let expectedAuthInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: pubKey,
            sequence: 42,
            gasLimit: entry.gasLimit * 3,
            feeDenom: entry.feeDenom,
            feeAmount: entry.feeAmount * 3
        )
        XCTAssertEqual(signDirect.authInfoBytes, expectedAuthInfo.base64EncodedString())
    }

    // MARK: - Preflight gating

    func testInvalidValidatorAddressIsRejectedBeforeSigning() {
        let payload = CosmosStakingPayload.delegate(
            validator: "terra1NOT_A_VALOPER",
            denom: "uluna",
            amount: "1000000"
        )
        let tx = Self.makeSendTransaction(payload: payload)

        XCTAssertThrowsError(
            try CosmosStakingSignDataResolver.resolve(
                sendTransaction: tx,
                chainSpecific: Self.makeChainSpecific()
            )
        ) { error in
            guard case CosmosStakingSignDataResolver.Errors.validatorPreflightFailed = error else {
                XCTFail("Expected validatorPreflightFailed, got \(error)")
                return
            }
        }
    }

    func testEmptyAmountIsRejectedForDelegate() {
        let payload = CosmosStakingPayload(
            opType: .delegate,
            validatorAddress: Self.validValidator,
            validatorSrcAddress: nil,
            validatorDstAddress: nil,
            validators: nil,
            denom: "uluna",
            amount: nil
        )
        let tx = Self.makeSendTransaction(payload: payload)

        XCTAssertThrowsError(
            try CosmosStakingSignDataResolver.resolve(
                sendTransaction: tx,
                chainSpecific: Self.makeChainSpecific()
            )
        ) { error in
            guard case CosmosStakingSignDataResolver.Errors.missingPayloadField(let field) = error else {
                XCTFail("Expected missingPayloadField, got \(error)")
                return
            }
            XCTAssertEqual(field, "amount")
        }
    }

    func testEmptyValidatorsListIsRejectedForWithdrawRewards() {
        let payload = CosmosStakingPayload.withdrawRewards(validators: [], denom: "uluna")
        let tx = Self.makeSendTransaction(payload: payload)

        XCTAssertThrowsError(
            try CosmosStakingSignDataResolver.resolve(
                sendTransaction: tx,
                chainSpecific: Self.makeChainSpecific()
            )
        ) { error in
            guard case CosmosStakingSignDataResolver.Errors.noValidatorsToClaim = error else {
                XCTFail("Expected noValidatorsToClaim, got \(error)")
                return
            }
        }
    }

    func testNonCosmosChainSpecificIsRejected() {
        let payload = CosmosStakingPayload.delegate(
            validator: Self.validValidator,
            denom: "uluna",
            amount: "1000000"
        )
        let tx = Self.makeSendTransaction(payload: payload)

        XCTAssertThrowsError(
            try CosmosStakingSignDataResolver.resolve(
                sendTransaction: tx,
                chainSpecific: .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 0)
            )
        ) { error in
            guard case CosmosStakingSignDataResolver.Errors.missingChainSpecific = error else {
                XCTFail("Expected missingChainSpecific, got \(error)")
                return
            }
        }
    }
}
