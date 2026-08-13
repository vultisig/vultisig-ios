//
//  FunctionTransactionKindTests.swift
//  VultisigAppTests
//
//  Which operation each builder says it is, and what the verify hero does with
//  that answer.
//

@testable import VultisigApp
import XCTest

@MainActor
final class FunctionTransactionKindTests: XCTestCase {

    // MARK: - The table

    /// Every `TransactionBuilder` in the app, and the verb it announces.
    ///
    /// ⚠️ **This pins regressions on the builders that exist. It cannot catch a
    /// NEW one.** Swift offers no reflection over the conformers of a protocol, so
    /// nothing here observes that a builder was added — a new builder with no
    /// `functionKind` compiles, ships, and silently announces "You're sending".
    /// That is the accepted cost of making the requirement optional (a required
    /// member would have forced every one of the ~28 conformers to answer, at the
    /// cost of a protocol that cannot be extended without touching all of them).
    /// The list below is maintained by hand; read it as a record of decisions
    /// taken, not as coverage.
    ///
    /// The `nil` rows are the load-bearing ones. Each is a builder whose `amount`
    /// is a carrier rather than the operation's figure — dust, a signalling fee, a
    /// fixed 1-CACAO placeholder — or whose figure is denominated in a coin the
    /// single-coin hero cannot name. Naming those operations would put a false
    /// number under a true verb, which is worse than the generic header they keep.
    ///
    /// ⚠️ **What this table cannot assert is the half that mattered most.** A
    /// builder's kind being right is only half of "does the screen tell the truth";
    /// the other half is whether the builder's own `coin` and `amount` name the
    /// thing that verb acts on, and no assertion can read that. It was decided per
    /// builder, and each decision is written at the `functionKind` it produced —
    /// mint versus redeem is the clearest case of the two answers differing on
    /// builders that otherwise look identical.
    func testEveryBuilderNamesTheOperationItPerforms() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let expected: [(String, TransactionBuilder, FunctionTransactionKind?)] = [
            // Staking
            ("TCYStake", TCYStakeTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false, isAutoCompound: false), .stake),
            ("RUJIStake", RUJIStakeTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false), .stake),
            ("RUJILiquidBond", RUJILiquidBondTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false), .stake),
            ("BRUNEStake", BRUNEStakeTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false), .stake),
            ("CacaoStake", CacaoStakeTransactionBuilder(coin: coin, amount: "1"), .stake),
            ("TonStake", TonStakeTransactionBuilder(
                coin: coin, amount: "1", poolAddress: "pool", memo: "d"), .stake),

            ("TCYUnstake", TCYUnstakeTransactionBuilder(
                coin: coin,
                basisPoints: 5000,
                autoCompoundAmount: 0,
                sendMaxAmount: false,
                isAutoCompound: false,
                stakedAmount: 100), .unstake),
            ("RUJIUnstake", RUJIUnstakeTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false), .unstake),
            ("RUJILiquidUnbond", RUJILiquidUnbondTransactionBuilder(
                coin: coin, percentage: 100, receiptShares: 10, sendMaxAmount: false), .unstake),
            ("BRUNEUnstake", BRUNEUnstakeTransactionBuilder(
                coin: coin, percentage: 100, autoCompoundAmount: 10, sendMaxAmount: false), .unstake),
            ("CacaoUnstake", CacaoUnstakeTransactionBuilder(
                coin: coin, bps: 5000, stakedAmount: 100), .unstake),
            ("SolanaUnstake", SolanaUnstakeTransactionBuilder(
                coin: coin, stakeAccount: "stake", delegatedAmount: 5), .unstake),

            // Node bonding
            ("Bond", BondTransactionBuilder(
                coin: coin,
                amount: "1",
                sendMaxAmount: false,
                nodeAddress: "thor1node",
                providerAddress: "",
                operatorFee: nil), .bond),
            ("Unbond", UnbondTransactionBuilder(
                coin: coin,
                unbondAmount: "1",
                sendMaxAmount: false,
                nodeAddress: "thor1node",
                providerAddress: ""), .unbond),

            // Cosmos / Solana staking
            ("CosmosDelegate", CosmosDelegateTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false, validatorAddress: "valoper"), .delegate),
            ("SolanaDelegate", SolanaDelegateTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false, votePubkey: "vote"), .delegate),
            ("CosmosUndelegate", CosmosUndelegateTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false, validatorAddress: "valoper"), .undelegate),
            ("CosmosRedelegate", CosmosRedelegateTransactionBuilder(
                coin: coin,
                amount: "1",
                sendMaxAmount: false,
                validatorSrcAddress: "src",
                validatorDstAddress: "dst"), .redelegate),

            // Rewards
            ("CosmosWithdrawRewards", CosmosWithdrawRewardsTransactionBuilder(
                coin: coin, validatorAddresses: ["valoper"]), .claimRewards),
            ("RUJIWithdrawRewards", RUJIWithdrawRewardsTransactionBuilder(
                coin: coin, withdrawAmount: "1", sendMaxAmount: false), .claimRewards),

            // yVault. ⚠️ The asymmetry is the point: redeem's `coin` is the
            // receipt being burned, so verb and figure agree, while mint's is the
            // coin being SPENT to mint a receipt whose quantity the transaction
            // never learns.
            ("Redeem", RedeemTransactionBuilder(
                coin: coin, amount: "1", sendMaxAmount: false, slippage: 0.01), .redeem),

            // Liquidity
            ("AddLP", AddLPTransactionBuilder(
                coin: coin,
                amount: "1",
                poolName: "BTC.BTC",
                pairedAddress: nil,
                sendMaxAmount: false), .addLiquidity),

            // ⚠️ Deliberately unnamed — see each builder's own note.
            ("RemoveLP", RemoveLPTransactionBuilder(
                coin: coin,
                amount: "0.02",
                poolName: "BTC.BTC",
                poolUnits: "1",
                percentage: 100,
                sendMaxAmount: false), nil),
            ("BondMaya", BondMayaTransactionBuilder(
                coin: coin,
                isBond: true,
                nodeAddress: "maya1node",
                selectedAsset: "BTC.BTC",
                lpUnits: 10), nil),
            ("TonUnstake", TonUnstakeTransactionBuilder(
                coin: coin, amount: "0.2", poolAddress: "pool", memo: "w"), nil),
            ("SolanaWithdraw", SolanaWithdrawTransactionBuilder(
                coin: coin, stakeAccount: "stake", amount: "1"), nil),
            ("Mint", MintTransactionBuilder(coin: coin, amount: "1", sendMaxAmount: false), nil),
            ("CancelLimitOrder", CancelLimitOrderTransactionBuilder(
                coin: coin, request: cancelRequest, l1Destination: nil), nil)
        ]

        for (name, builder, kind) in expected {
            XCTAssertEqual(builder.functionKind, kind, "\(name) announces the wrong operation")
        }
    }

    /// A kind that reaches the screen as its raw key is a missing translation, and
    /// the verify hero is the last place to discover one.
    func testEveryKindResolvesToTranslatedCopy() {
        for kind in FunctionTransactionKind.allCases {
            let title = kind.verifyTitle
            XCTAssertFalse(title.isEmpty, "\(kind) has no title")
            XCTAssertFalse(title.hasPrefix("youre"), "\(kind) rendered its raw key: \(title)")
        }
    }

    // MARK: - What the hero does with the answer

    /// The carried figure wins when there is one — that is the whole reason it
    /// exists, since these transactions' own `amount` is a literal "0".
    func testTheHeroQuotesTheCarriedFigureWhenThereIsOne() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let transaction = makeTransaction(amount: "0", withdrawDisplayAmount: 12.5, functionKind: .unbond)
        let hero = try XCTUnwrap(FunctionTransactionPresentation.hero(for: transaction))
        guard case .send(let title, let rendered) = hero else {
            return XCTFail("a named operation renders as a resolved single-sided amount")
        }
        XCTAssertEqual(title, FunctionTransactionKind.unbond.verifyTitle)
        XCTAssertEqual(rendered.amount, Decimal(12.5).formatToDecimal(digits: transaction.coin.decimals))
        XCTAssertEqual(rendered.ticker, transaction.coin.ticker)
    }

    /// …and the transaction's own amount is used when there is not. Most operations
    /// are this case: they have a perfectly good amount and only needed the verb.
    func testTheHeroFallsBackToTheTransactionsOwnAmount() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let transaction = makeTransaction(amount: "3.25", withdrawDisplayAmount: nil, functionKind: .stake)
        let hero = try XCTUnwrap(FunctionTransactionPresentation.hero(for: transaction))
        guard case .send(let title, let rendered) = hero else {
            return XCTFail("a named operation renders as a resolved single-sided amount")
        }
        XCTAssertEqual(title, FunctionTransactionKind.stake.verifyTitle)
        XCTAssertEqual(rendered.amount, Decimal(string: "3.25")!.formatToDecimal(digits: transaction.coin.decimals))
    }

    /// ⚠️ The real-funds guard. A builder can legitimately know what it is doing
    /// and still have no figure to quote — a share-based redemption, a rewards
    /// claim whose message carries no Coin — and its `amount` is then a placeholder
    /// zero. Announcing that zero under a correct verb would be the defect this
    /// hero exists to remove, so the hero declines and the screen keeps its
    /// generic header.
    func testANamedOperationWithNoFigureGetsNoHeroRatherThanAZero() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        XCTAssertNil(FunctionTransactionPresentation.hero(
            for: makeTransaction(amount: "0", withdrawDisplayAmount: nil, functionKind: .unstake)
        ))
        XCTAssertNil(FunctionTransactionPresentation.hero(
            for: makeTransaction(amount: "", withdrawDisplayAmount: nil, functionKind: .claimRewards)
        ))
    }

    /// An unnamed transaction is every send in the app, and none of them may grow
    /// a hero from this provider.
    func testAnUnnamedTransactionGetsNoHero() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        XCTAssertNil(FunctionTransactionPresentation.hero(
            for: makeTransaction(amount: "10", withdrawDisplayAmount: nil, functionKind: nil)
        ))
    }

    // MARK: - Fixtures

    private var coin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .thorChain,
                ticker: "RUNE",
                logo: "rune",
                decimals: 8,
                priceProviderId: "thorchain",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "thor1sender",
            hexPublicKey: "HexPublicKeyExample"
        )
    }

    private var cancelRequest: LimitOrderCancelRequest {
        LimitOrderCancelRequest(
            orderId: "order-1",
            inboundTxHash: "ABC123",
            memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            sourceChainRawValue: Chain.thorChain.rawValue,
            duplicateRestingOrderCount: 0
        )
    }

    private func makeTransaction(
        amount: String,
        withdrawDisplayAmount: Decimal?,
        functionKind: FunctionTransactionKind?
    ) -> SendTransaction {
        let coin = coin
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            withdrawDisplayAmount: withdrawDisplayAmount,
            functionKind: functionKind
        )
    }
}
