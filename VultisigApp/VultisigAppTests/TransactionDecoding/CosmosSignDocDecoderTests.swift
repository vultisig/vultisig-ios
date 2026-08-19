//
//  CosmosSignDocDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

final class CosmosSignDocDecoderTests: XCTestCase {

    func testInitiatorAndCosignerHeroesMatchForEveryStakingOperation() {
        let denom = Chain.terra.feeUnit
        let amount = "1250000"
        let validatorA = "terravaloper1source"
        let validatorB = "terravaloper1destination"
        let delegator = "terra1delegator"
        let cases: [(String, CosmosStakingPayload, [Data], DecodedOperation)] = [
            (
                "delegate",
                .delegate(validator: validatorA, denom: denom, amount: amount),
                [CosmosStakingHelper.encodeDelegate(
                    delegator: delegator, validator: validatorA, amount: amount, denom: denom
                )],
                .delegate
            ),
            (
                "undelegate",
                .undelegate(validator: validatorA, denom: denom, amount: amount),
                [CosmosStakingHelper.encodeUndelegate(
                    delegator: delegator, validator: validatorA, amount: amount, denom: denom
                )],
                .undelegate
            ),
            (
                "redelegate",
                .redelegate(src: validatorA, dst: validatorB, denom: denom, amount: amount),
                [CosmosStakingHelper.encodeBeginRedelegate(
                    delegator: delegator,
                    validatorSrc: validatorA,
                    validatorDst: validatorB,
                    amount: amount,
                    denom: denom
                )],
                .redelegate
            ),
            (
                "claim rewards",
                .withdrawRewards(validators: [validatorA, validatorB], denom: denom),
                [validatorA, validatorB].map {
                    CosmosStakingHelper.encodeWithdrawDelegatorReward(delegator: delegator, validator: $0)
                },
                .claimRewards
            )
        ]

        for (name, intent, messages, operation) in cases {
            let transaction = Self.transaction(intent: intent)
            let payload = Self.payload(
                chain: .terra,
                transactionType: .unspecified,
                body: CosmosStakingHelper.buildTxBodyMulti(msgsAny: messages)
            )
            let initiator = SignedTransactionDecoder.decode(InitiatingTransactionContent(transaction))
            let cosigner = SignedTransactionDecoder.decode(payload)

            XCTAssertEqual(initiator.operation, operation, name)
            XCTAssertEqual(initiator.operation, cosigner.operation, name)
            XCTAssertEqual(initiator.amount, cosigner.amount, name)
            XCTAssertEqual(initiator.counterparty, cosigner.counterparty, name)
            XCTAssertEqual(
                TransactionHeroResolver.hero(on: .functionCallVerify, for: .initiating(transaction)),
                TransactionHeroResolver.hero(
                    on: .keysignConfirm,
                    for: .cosigning(payload: payload, simulated: { nil })
                ),
                name
            )
        }
    }

    func testRewardsHeroStatesItsScopeWithoutInventingAnAmount() {
        let intent = CosmosStakingPayload.withdrawRewards(
            validators: ["terravaloper1validator"],
            denom: Chain.terra.feeUnit
        )
        let hero = TransactionHeroResolver.hero(
            on: .functionCallVerify,
            for: .initiating(Self.transaction(intent: intent))
        )
        guard case .projected(_, let estimate, let scope) = hero else {
            return XCTFail("a rewards claim should state its signed scope without inventing an amount")
        }
        XCTAssertNil(estimate)
        XCTAssertEqual(scope, "scopeRewardsAccruedSoFar".localized)
    }

    @MainActor
    func testExactStakingHeroIncludesFiat() throws {
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "terra-luna-2", value: 1)
        ])
        let intent = CosmosStakingPayload.delegate(
            validator: "terravaloper1validator",
            denom: Chain.terra.feeUnit,
            amount: "1250000"
        )
        let hero = try XCTUnwrap(
            TransactionHeroResolver.hero(
                on: .functionCallVerify,
                for: .initiating(Self.transaction(intent: intent))
            )
        )

        guard case .send(_, let amount) = hero else {
            return XCTFail("expected an exact delegation amount")
        }
        XCTAssertEqual(amount.amount, "1.25")
        XCTAssertFalse(amount.fiat?.isEmpty ?? true)
    }

    func testSignDocBodyIsReadOnlyOnRoutesThatConsumeIt() {
        let accepted: [(Chain, VSTransactionType)] = [
            (.gaiaChain, .unspecified),
            (.gaiaChain, .genericContract),
            (.terra, .ibcTransfer),
            (.terraClassic, .vote),
            (.dydx, .unspecified),
            (.qbtc, .ibcTransfer)
        ]
        for (chain, type) in accepted {
            XCTAssertEqual(
                SignedTransactionDecoder.decode(Self.payload(chain: chain, transactionType: type)).operation,
                .delegate,
                "\(chain) \(type)"
            )
        }
    }

    func testSignDocBodyIsIgnoredWhenTheHelperBuildsAnotherBody() {
        let rejected: [(Chain, VSTransactionType)] = [
            (.gaiaChain, .ibcTransfer),
            (.osmosis, .vote),
            (.dydx, .vote)
        ]
        for (chain, type) in rejected {
            XCTAssertEqual(
                SignedTransactionDecoder.decode(Self.payload(chain: chain, transactionType: type)).operation,
                .unknown,
                "\(chain) \(type)"
            )
        }
    }

    func testApproveAndSwapRoutesOutrankSignDoc() {
        let approve = Self.payload(
            chain: .gaiaChain,
            transactionType: .unspecified,
            approve: ERC20ApprovePayload(amount: 1, spender: "router")
        )
        let swap = Self.payload(
            chain: .gaiaChain,
            transactionType: .unspecified,
            swap: .thorchain(Self.swapPayload())
        )

        XCTAssertEqual(SignedTransactionDecoder.decode(approve).operation, .unknown)
        XCTAssertEqual(SignedTransactionDecoder.decode(swap).operation, .unknown)
    }

    func testCosmosMemoAndWireDecoderOperations() {
        let decoder = CosmosTransactionDecoder()
        let switching = decoder.decode(Self.payload(
            chain: .gaiaChain,
            transactionType: .unspecified,
            body: nil,
            memo: "SWITCH:thor1destination"
        ))
        let ibc = decoder.decode(Self.payload(
            chain: .gaiaChain,
            transactionType: .ibcTransfer,
            body: nil
        ))
        let vote = decoder.decode(Self.payload(
            chain: .dydx,
            transactionType: .vote,
            body: nil,
            memo: "DYDX_VOTE:YES:42"
        ))

        XCTAssertEqual(switching?.operation, .switchChain)
        XCTAssertEqual(switching?.amount, .units(BigInt(1), of: .transactionCoin))
        XCTAssertEqual(ibc?.operation, .ibcTransfer)
        XCTAssertEqual(vote?.operation, .vote)
        XCTAssertEqual(vote?.amount, .unstated)
    }

    func testApproveOutranksCosmosMemoDecoder() {
        let payload = Self.payload(
            chain: .gaiaChain,
            transactionType: .unspecified,
            body: nil,
            memo: "SWITCH:thor1destination",
            approve: ERC20ApprovePayload(amount: 1, spender: "router")
        )
        XCTAssertNil(CosmosTransactionDecoder().decode(payload))
    }

    private static func payload(
        chain: Chain,
        transactionType: VSTransactionType,
        body: Data? = delegateBody,
        memo: String? = nil,
        approve: ERC20ApprovePayload? = nil,
        swap: SwapPayload? = nil
    ) -> KeysignPayload {
        let coin = Self.coin(chain: chain)
        return KeysignPayload(
            coin: coin,
            toAddress: "cosmos1destination",
            toAmount: BigInt(1),
            chainSpecific: .Cosmos(
                accountNumber: 1,
                sequence: 1,
                gas: 1,
                transactionType: transactionType.rawValue,
                ibcDenomTrace: nil,
                gasLimit: nil
            ),
            utxos: [],
            memo: memo,
            swapPayload: swap,
            approvePayload: approve,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: body.map {
                .signDirect(SignDirect(
                    bodyBytes: $0.base64EncodedString(),
                    authInfoBytes: "",
                    chainID: "test-1",
                    accountNumber: "1"
                ))
            }
        )
    }

    private static var delegateBody: Data {
        CosmosStakingHelper.buildTxBodyMulti(msgsAny: [
            CosmosStakingHelper.encodeDelegate(
                delegator: "cosmos1delegator",
                validator: "cosmosvaloper1validator",
                amount: "1000000",
                denom: "uatom"
            )
        ])
    }

    private static func transaction(intent: CosmosStakingPayload) -> SendTransaction {
        let coin = Self.coin(chain: .terra)
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: intent.validatorAddress ?? intent.validatorDstAddress ?? "",
            toAddressLabel: nil,
            amount: intent.amount == nil ? "0" : "1.25",
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
            cosmosStakingPayload: intent
        )
    }

    private static func coin(chain: Chain) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: chain.ticker,
                logo: chain.logo,
                decimals: 6,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "cosmos1delegator",
            hexPublicKey: "00"
        )
    }

    private static func swapPayload() -> THORChainSwapPayload {
        let coin = coin(chain: .gaiaChain)
        return THORChainSwapPayload(
            fromAddress: coin.address,
            fromCoin: coin,
            toCoin: coin,
            vaultAddress: "cosmos1vault",
            routerAddress: nil,
            fromAmount: 1,
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }
}
