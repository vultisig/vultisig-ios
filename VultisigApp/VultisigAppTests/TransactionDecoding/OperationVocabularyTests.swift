//
//  OperationVocabularyTests.swift
//  VultisigAppTests
//
//  Requires an explicit presentation decision for every decoded operation.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import WalletCore
import XCTest

final class OperationVocabularyTests: XCTestCase {

    private struct DecoderFixture {
        let name: String
        let operation: DecodedOperation
        let payload: KeysignPayload
    }

    /// Exercises every registry operation except screen-owned swap and approve.
    func testEveryOperationHasBehavioralUnitCoverage() {
        let fixtures = Self.decoderFixtures
        let screenOwned: Set<DecodedOperation> = [.swap, .approve]

        XCTAssertEqual(
            Set(fixtures.map(\.operation)).union(screenOwned),
            Set(DecodedOperation.allCases),
            "an operation was added without a real decoder fixture or an explicit screen-owned exemption"
        )
        for fixture in fixtures {
            XCTAssertEqual(
                SignedTransactionDecoder.decode(fixture.payload).operation,
                fixture.operation,
                fixture.name
            )
        }
    }

    /// Decoder coverage and wording coverage are separate contracts. This walks
    /// every case through the actual hero builder, ensuring named operations
    /// produce their own title and deliberately silent operations produce none.
    func testEveryOperationProducesItsExpectedHeroBehavior() {
        let decodedByOperation = Self.decoderFixtures.reduce(into: [DecodedOperation: DecodedTransaction]()) { readings, fixture in
            if readings[fixture.operation] == nil {
                readings[fixture.operation] = SignedTransactionDecoder.decode(fixture.payload)
            }
        }
        let coin = Self.coin(chain: .thorChain)

        for operation in DecodedOperation.allCases {
            let decoded = decodedByOperation[operation] ?? DecodedTransaction(
                operation: operation,
                amount: .unstated,
                evidence: .structuredPayload
            )
            let hero = DecodedTransactionPresentation.hero(for: decoded, coin: coin)

            if let expectedTitle = DecodedTransactionPresentation.title(for: operation) {
                XCTAssertEqual(hero?.title, expectedTitle, "\(operation) rendered the wrong hero title")
            } else {
                XCTAssertNil(hero, "\(operation) is deliberately silent but rendered a hero")
            }
        }
    }

    /// Every operation is either named or deliberately silent.
    func testEveryOperationIsNamedOrDeliberatelySilent() {
        for operation in DecodedOperation.allCases {
            let named = DecodedTransactionPresentation.title(for: operation) != nil
            let silent = DecodedTransactionPresentation.deliberatelySilent[operation] != nil

            XCTAssertTrue(
                named || silent,
                """
                \(operation) has no verb and no reason for not having one. Either \
                give it a title in `title(for:)` — with the key present in all \
                eight shipping locales — or add it to `deliberatelySilent` saying \
                what would have to change.
                """
            )
        }
    }

    /// No operation can be both named and silent.
    func testNoOperationIsBothNamedAndSilent() {
        for operation in DecodedOperation.allCases {
            let named = DecodedTransactionPresentation.title(for: operation) != nil
            let silent = DecodedTransactionPresentation.deliberatelySilent[operation] != nil
            XCTAssertFalse(named && silent, "\(operation) is named AND listed as silent")
        }
    }

    /// Every silent operation records why.
    func testEverySilentOperationStatesWhy() {
        for (operation, reason) in DecodedTransactionPresentation.deliberatelySilent {
            XCTAssertFalse(
                reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(operation) is listed as silent with an empty reason"
            )
        }
    }

    /// Pins operation-to-verb semantics, not merely key existence.
    func testEachNamedOperationUsesItsOwnVerb() {
        let expected: [DecodedOperation: String] = [
            .stake: "youreStaking",
            .unstake: "youreUnstaking",
            .claimRewards: "youreClaiming",
            .bond: "youreBonding",
            .unbond: "youreUnbonding",
            .rebond: "youreRebonding",
            .leave: "youreLeaving",
            .securedAssetDeposit: "youreDepositing",
            .securedAssetWithdraw: "youreWithdrawing",
            .switchChain: "youreSwitching",
            .limitOrderPlacement: "yourePlacingOrder",
            .limitOrderCancel: "youreCancellingOrder",
            .delegate: "youreDelegating",
            .undelegate: "youreUndelegating",
            .redelegate: "youreRedelegating",
            .addLiquidity: "youreAddingLiquidity",
            .removeLiquidity: "youreRemovingLiquidity",
            .redeem: "youreRedeeming",
            .withdrawStake: "youreWithdrawing",
            .mint: "youreMinting",
            .merge: "youreMerging",
            .unmerge: "youreUnmerging",
            .ibcTransfer: "youreBridging"
        ]

        for (operation, key) in expected {
            XCTAssertEqual(
                DecodedTransactionPresentation.localizationKey(for: operation), key,
                "\(operation) is wired to the wrong verb"
            )
        }

        let named = DecodedOperation.allCases.filter {
            DecodedTransactionPresentation.localizationKey(for: $0) != nil
        }
        XCTAssertEqual(
            Set(named), Set(expected.keys),
            "an operation gained or lost a verb without this mapping being updated"
        )
    }

    /// Every named operation resolves in every shipping locale.
    func testEveryNamedOperationResolvesInEveryShippingLocale() throws {
        let locales = ["en", "de", "es", "hr", "it", "ko", "pt", "zh-Hans"]

        // Keep this list synchronized with the bundle's shipping locales.
        let shipped = Set(Bundle.main.localizations).subtracting(["Base"])
        XCTAssertEqual(
            Set(locales), shipped,
            "the app's shipping locales changed — every named verb needs copy in the new set"
        )

        for operation in DecodedOperation.allCases {
            guard let key = DecodedTransactionPresentation.localizationKey(for: operation) else { continue }

            for locale in locales {
                let bundle = try XCTUnwrap(
                    Bundle(for: Self.self).path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:))
                        ?? Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:)),
                    "no \(locale).lproj in the bundle"
                )

                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(
                    value, key,
                    "\(operation) has no verb in \(locale) — `\(key)` is missing, so that locale shows the raw key"
                )
            }
        }
    }

    func testEveryOperationHasAnExplicitDoneVocabularyDecision() {
        let expected: [DecodedOperation: String?] = [
            .transfer: "doneVerbSent",
            .swap: nil,
            .approve: "doneVerbApproved",
            .stake: "doneVerbStaked",
            .unstake: "doneVerbUnstaked",
            .bond: "doneVerbBonded",
            .unbond: "doneVerbUnbonded",
            .rebond: "doneVerbRebonded",
            .leave: "doneVerbLeft",
            .delegate: "doneVerbDelegated",
            .undelegate: "doneVerbUndelegated",
            .redelegate: "doneVerbRedelegated",
            .claimRewards: "doneVerbClaimedRewards",
            .mint: "doneVerbMinted",
            .redeem: "doneVerbRedeemed",
            .withdrawStake: "doneVerbWithdrew",
            .addLiquidity: "doneVerbAddedLiquidity",
            .removeLiquidity: "doneVerbRemovedLiquidity",
            .merge: "doneVerbMerged",
            .unmerge: "doneVerbUnmerged",
            .ibcTransfer: "doneVerbBridged",
            .vote: "doneVerbVoted",
            .securedAssetDeposit: "doneVerbDeposited",
            .securedAssetWithdraw: "doneVerbWithdrew",
            .switchChain: "doneVerbSwitched",
            .limitOrderPlacement: "doneVerbPlacedLimitOrder",
            .limitOrderCancel: "limitSwap.cancel.done.sent",
            .contractCall: "doneVerbSent",
            .unknown: "doneVerbSent"
        ]

        XCTAssertEqual(Set(expected.keys), Set(DecodedOperation.allCases))
        for operation in DecodedOperation.allCases {
            XCTAssertEqual(
                DecodedTransactionPresentation.doneLocalizationKey(for: operation),
                expected[operation] ?? nil,
                "\(operation) has the wrong Done vocabulary decision"
            )
        }
    }

    func testEveryDoneVerbResolvesInEveryShippingLocale() throws {
        let locales = ["en", "de", "es", "hr", "it", "ko", "pt", "zh-Hans"]
        let keys = Set(DecodedOperation.allCases.compactMap {
            DecodedTransactionPresentation.doneLocalizationKey(for: $0)
        })

        for key in keys {
            for locale in locales {
                let bundle = try XCTUnwrap(
                    Bundle(for: Self.self).path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:))
                        ?? Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:)),
                    "no \(locale).lproj in the bundle"
                )
                XCTAssertNotEqual(
                    bundle.localizedString(forKey: key, value: nil, table: nil),
                    key,
                    "Done verb `\(key)` is missing in \(locale)"
                )
            }
        }
    }

    // MARK: - Exhaustive decoder fixtures

    private static var decoderFixtures: [DecoderFixture] {
        let thorMemos: [(String, DecodedOperation)] = [
            ("tcy+", .stake),
            ("tcy-:5006", .unstake),
            ("BOND:thor1node", .bond),
            ("UNBOND:thor1node:100", .unbond),
            ("REBOND:thor1node:thor1newnode", .rebond),
            ("LEAVE:thor1node", .leave),
            ("claim:thor1contract:100", .claimRewards),
            ("+:BTC.BTC", .addLiquidity),
            ("-:BTC.BTC:5006", .removeLiquidity),
            ("MERGE:thor1token", .merge),
            ("UNMERGE:thor1token:100", .unmerge),
            ("SECURE+:thor1destination", .securedAssetDeposit),
            ("SECURE-:thor1destination", .securedAssetWithdraw),
            ("=<:100000000THOR.RUNE:15979057441BTC.BTC:0", .limitOrderPlacement),
            ("m=<:100000000THOR.RUNE:15979057441BTC.BTC:0", .limitOrderCancel)
        ]
        var fixtures = thorMemos.map { memo, operation in
            DecoderFixture(
                name: "THORChain memo \(memo)",
                operation: operation,
                payload: payload(chain: .thorChain, memo: memo)
            )
        }

        fixtures.append(contentsOf: [
            DecoderFixture(
                name: "yVault deposit",
                operation: .mint,
                payload: payload(chain: .thorChain, wasm: vaultWasm(action: "deposit"))
            ),
            DecoderFixture(
                name: "yVault withdraw",
                operation: .redeem,
                payload: payload(chain: .thorChain, wasm: vaultWasm(action: "withdraw"))
            ),
            DecoderFixture(
                name: "unknown wasm action",
                operation: .contractCall,
                payload: payload(chain: .thorChain, wasm: unknownWasm)
            ),
            cosmosStakingFixture(
                name: "Cosmos delegate",
                operation: .delegate,
                message: CosmosStakingHelper.encodeDelegate(
                    delegator: "cosmos1delegator",
                    validator: "cosmosvaloper1validator",
                    amount: "1000000",
                    denom: "uatom"
                )
            ),
            cosmosStakingFixture(
                name: "Cosmos undelegate",
                operation: .undelegate,
                message: CosmosStakingHelper.encodeUndelegate(
                    delegator: "cosmos1delegator",
                    validator: "cosmosvaloper1validator",
                    amount: "1000000",
                    denom: "uatom"
                )
            ),
            cosmosStakingFixture(
                name: "Cosmos redelegate",
                operation: .redelegate,
                message: CosmosStakingHelper.encodeBeginRedelegate(
                    delegator: "cosmos1delegator",
                    validatorSrc: "cosmosvaloper1source",
                    validatorDst: "cosmosvaloper1destination",
                    amount: "1000000",
                    denom: "uatom"
                )
            ),
            cosmosStakingFixture(
                name: "Cosmos claim rewards",
                operation: .claimRewards,
                message: CosmosStakingHelper.encodeWithdrawDelegatorReward(
                    delegator: "cosmos1delegator",
                    validator: "cosmosvaloper1validator"
                )
            ),
            DecoderFixture(
                name: "Cosmos MsgSend",
                operation: .transfer,
                payload: payload(chain: .gaiaChain, signBody: cosmosSendBody)
            ),
            DecoderFixture(
                name: "Cosmos IBC transfer",
                operation: .ibcTransfer,
                payload: payload(chain: .gaiaChain, transactionType: .ibcTransfer)
            ),
            DecoderFixture(
                name: "Cosmos vote",
                operation: .vote,
                payload: payload(chain: .gaiaChain, transactionType: .vote)
            ),
            DecoderFixture(
                name: "Cosmos switch",
                operation: .switchChain,
                payload: payload(chain: .gaiaChain, memo: "SWITCH:thor1destination")
            ),
            DecoderFixture(
                name: "Solana stake-account withdraw",
                operation: .withdrawStake,
                payload: solanaWithdrawPayload
            ),
            DecoderFixture(
                name: "unread transaction",
                operation: .unknown,
                payload: payload(chain: .thorChain)
            )
        ])
        return fixtures
    }

    private static func cosmosStakingFixture(
        name: String,
        operation: DecodedOperation,
        message: Data
    ) -> DecoderFixture {
        DecoderFixture(
            name: name,
            operation: operation,
            payload: payload(
                chain: .gaiaChain,
                signBody: CosmosStakingHelper.buildTxBodyMulti(msgsAny: [message])
            )
        )
    }

    private static func payload(
        chain: Chain,
        memo: String? = nil,
        transactionType: VSTransactionType = .unspecified,
        wasm: WasmExecuteContractPayload? = nil,
        signBody: Data? = nil
    ) -> KeysignPayload {
        let coin = coin(chain: chain)
        let chainSpecific: BlockChainSpecific = chain == .gaiaChain
            ? .Cosmos(
                accountNumber: 1,
                sequence: 1,
                gas: 1,
                transactionType: transactionType.rawValue,
                ibcDenomTrace: nil,
                gasLimit: nil
            )
            : .THORChain(accountNumber: 1, sequence: 1, fee: 1, isDeposit: true)

        return KeysignPayload(
            coin: coin,
            toAddress: chain == .gaiaChain ? "cosmos1destination" : "thor1destination",
            toAmount: BigInt(100_000_000),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: wasm,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signBody.map {
                .signDirect(SignDirect(
                    bodyBytes: $0.base64EncodedString(),
                    authInfoBytes: "",
                    chainID: "cosmoshub-4",
                    accountNumber: "1"
                ))
            }
        )
    }

    private static func coin(chain: Chain) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: chain.ticker,
                logo: chain.logo,
                decimals: 8,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            ),
            address: chain == .gaiaChain ? "cosmos1sender" : "thor1sender",
            hexPublicKey: "00"
        )
    }

    private static var solanaWithdrawPayload: KeysignPayload {
        let coin = Coin(
            asset: CoinMeta(
                chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
                priceProviderId: "solana", contractAddress: "", isNativeToken: true
            ),
            address: "owner", hexPublicKey: "00"
        )
        return KeysignPayload(
            coin: coin,
            toAddress: "owner",
            toAmount: .zero,
            chainSpecific: .Solana(
                recentBlockHash: "11111111111111111111111111111111",
                priorityFee: 0,
                priorityLimit: 0,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "pub", vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(), wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil, tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil, qbtcClaimPayload: nil,
            isQbtcClaim: false, skipBroadcast: false,
            signData: .signSolana(SignSolana(rawTransactions: [solanaWithdrawTransaction]))
        )
    }

    private static var solanaWithdrawTransaction: String {
        let stakeProgram = Base58.decodeNoCheck(
            string: "Stake11111111111111111111111111111111111111"
        )!
        let accounts = [
            stakeProgram,
            Data(repeating: 0x01, count: 32),
            Data(repeating: 0x02, count: 32),
            Data(repeating: 0x03, count: 32),
            Data(repeating: 0x04, count: 32),
            Data(repeating: 0x05, count: 32)
        ]
        let data = littleEndian(UInt32(4)) + littleEndian(UInt64(2_100_000_000))

        var transaction = compactU16(1) + Data(repeating: 0, count: 64)
        transaction += Data([1, 0, 1])
        transaction += compactU16(accounts.count)
        accounts.forEach { transaction += $0 }
        transaction += Data(repeating: 0, count: 32)
        transaction += compactU16(1)
        transaction += Data([0])
        transaction += compactU16(5)
        transaction += Data([1, 2, 3, 4, 5])
        transaction += compactU16(data.count)
        transaction += data
        return transaction.base64EncodedString()
    }

    private static func compactU16(_ value: Int) -> Data {
        value < 0x80 ? Data([UInt8(value)]) : Data([UInt8(value & 0x7F | 0x80), UInt8(value >> 7)])
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        Data((0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }

    private static func vaultWasm(action: String) -> WasmExecuteContractPayload {
        let inner = "{\"\(action)\":{}}"
        let encoded = Data(inner.utf8).base64EncodedString()
        return WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1vault",
            executeMsg: "{\"execute\":{\"msg\":\"\(encoded)\"}}",
            coins: [CosmosCoin(amount: "100000000", denom: "rune")]
        )
    }

    private static var unknownWasm: WasmExecuteContractPayload {
        WasmExecuteContractPayload(
            senderAddress: "thor1sender",
            contractAddress: "thor1contract",
            executeMsg: "{\"mystery\":{}}",
            coins: []
        )
    }

    private static var cosmosSendBody: Data {
        var coin = Data()
        coin.appendProtoString(fieldNumber: 1, value: "uatom")
        coin.appendProtoString(fieldNumber: 2, value: "1000000")

        var message = Data()
        message.appendProtoString(fieldNumber: 1, value: "cosmos1sender")
        message.appendProtoString(fieldNumber: 2, value: "cosmos1destination")
        message.appendProtoBytes(fieldNumber: 3, data: coin)

        var any = Data()
        any.appendProtoString(fieldNumber: 1, value: "/cosmos.bank.v1beta1.MsgSend")
        any.appendProtoBytes(fieldNumber: 2, data: message)
        return CosmosStakingHelper.buildTxBodyMulti(msgsAny: [any])
    }
}
