//
//  TransactionHeroResolverTests.swift
//  VultisigAppTests
//
//  Precedence used to be implicit: each screen wrote its own `??` chain, so the
//  order lived four times over in view code and nothing could assert it. These
//  tests pin the registry itself — the order providers are asked in, and which
//  surface asks which — so that changing either is a deliberate edit to a failing
//  expectation rather than a silent reshuffle of what a user is told they are
//  signing.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

@MainActor
final class TransactionHeroResolverTests: XCTestCase {

    private static let account = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    private static let issuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"

    private let staked = Decimal(string: "2002.74")!
    private let cancelMemo = "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"
    private let placementMemo = "=<:BTC.BTC:bc1qdest:16e8/1200/0::0"

    // MARK: - The registry itself

    /// The declared order. Screens no longer each hand-order their fallbacks, so
    /// this array is the only statement of precedence in the app.
    func testProvidersAreAskedInTheDeclaredOrder() {
        XCTAssertEqual(
            TransactionHeroResolver.providers.map(\.id),
            [.rippleTrustSet, .limitOrderCancel, .limitOrderPlacement, .functionTransaction]
        )
    }

    /// A provider registered twice would be asked twice and, worse, would make the
    /// grid below ambiguous about which entry a surface got.
    func testEveryProviderIsRegisteredExactlyOnce() {
        let ids = TransactionHeroResolver.providers.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(TransactionHeroProvider.ID.allCases))
    }

    /// ⚠️ The surface grid, as it was before the resolver existed.
    ///
    /// The differences between rows are real and were preserved deliberately, not
    /// tidied away. `functionTransaction` speaks only on the initiator's
    /// function-call Verify even though the same transaction reaches
    /// `SendDoneScreen` with its `functionKind` intact; `rippleTrustSet` is absent
    /// from the co-signer's Verify, which renders the trust line's terms as its own
    /// rows; `limitOrderPlacement` is co-signer-only because the initiator's
    /// placement is verified on a different screen entirely. Widening any row is a
    /// product change, and this test is what makes it look like one.
    func testEachSurfaceAsksExactlyTheProvidersItAskedBefore() {
        let expected: [TransactionHeroSurface: [TransactionHeroProvider.ID]] = [
            .functionCallVerify: [.limitOrderCancel, .functionTransaction],
            .sendDone: [.rippleTrustSet, .limitOrderCancel],
            .keysignConfirm: [.limitOrderCancel, .limitOrderPlacement],
            .keysignDone: [.rippleTrustSet, .limitOrderCancel]
        ]

        for surface in TransactionHeroSurface.allCases {
            let asked = TransactionHeroResolver.providers
                .filter { $0.surfaces.contains(surface) }
                .map(\.id)
            XCTAssertEqual(asked, expected[surface], "surface \(surface)")
        }
    }

    /// The weaker, live property: nothing any builder actually emits is claimed by
    /// two providers, so today the order never decides anything. Worth pinning
    /// because it is the reason four screens could be merged onto one list at all
    /// — but it is a fact about the builders, not an invariant, which is what the
    /// next test is for.
    func testNothingTheBuildersEmitIsClaimedTwice() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let subjects: [TransactionHeroSubject] = [
            .initiating(try makeTCYWithdrawal()),
            .initiating(makeCancelTransaction()),
            .initiating(SendTransaction.empty(coin: makeRune(), vault: .example)),
            .cosigning(makePayload(memo: cancelMemo)),
            .cosigning(makePayload(memo: placementMemo)),
            .cosigning(makeTrustSetPayload()),
            .cosigning(makePayload(memo: nil))
        ]

        for subject in subjects {
            let claims = TransactionHeroResolver.providers.compactMap { $0.hero(subject) }
            XCTAssertLessThanOrEqual(claims.count, 1, "more than one provider claimed the same subject")
        }
    }

    /// ⚠️ **The order is real precedence, and these are the overlaps the types
    /// permit.** `SendTransaction` will carry a `functionKind` and a
    /// `limitCancelContext` at the same time if someone constructs one, and an
    /// XRPL TrustSet payload can carry any memo, `m=<` included. No builder emits
    /// either combination today — but "no builder does" is not an invariant, and
    /// when one starts to, the hero must not change under the screens.
    ///
    /// The one pair genuinely excluded by construction is cancel vs placement:
    /// `m=<` and `=<` are different prefixes and `m=<…` does not start with `=<`,
    /// so no memo is both.
    func testTheOrderDecidesWhenTwoProvidersBothClaim() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        // ⚠️ The CANCEL wins, and that is a deliberate reversal of the order the
        // withdrawal-only provider had.
        //
        // That provider fired on a `withdrawDisplayAmount`, which only a staked
        // withdrawal ever carried, so putting it first cost nothing. Its successor
        // answers for EVERY named DeFi operation, which makes it the broadest
        // claim on the list — and a transaction that is a limit-order cancel is a
        // cancel first, whatever else it also managed to say about itself. A
        // cancel moves nothing (or donated dust); letting the generic hero quote
        // that dust as the operation's amount is exactly the failure the cancel
        // hero was written to prevent.
        let withdrawalAndCancel = try makeTCYWithdrawalAlsoCarryingACancel()
        XCTAssertEqual(
            TransactionHeroResolver.hero(on: .functionCallVerify, for: withdrawalAndCancel),
            LimitOrderCancelPresentation.hero(for: withdrawalAndCancel)
        )
        XCTAssertNotNil(TransactionHeroResolver.hero(on: .functionCallVerify, for: withdrawalAndCancel))
        // Both really do claim it — otherwise the assertion above would pass for
        // the wrong reason.
        XCTAssertNotNil(FunctionTransactionPresentation.hero(for: withdrawalAndCancel))

        // `RippleTrustSetPresentation.hero ?? LimitOrderCancelPresentation.hero` —
        // the trust line won on the initiator's Done.
        let trustSetAndCancel = makeTrustSetTransactionAlsoCarryingACancel()
        XCTAssertEqual(
            TransactionHeroResolver.hero(on: .sendDone, for: trustSetAndCancel),
            RippleTrustSetPresentation.hero(for: trustSetAndCancel)
        )
        XCTAssertNotNil(TransactionHeroResolver.hero(on: .sendDone, for: trustSetAndCancel))

        // Same order on the co-signer's Done, where the overlap is a TrustSet
        // payload that also carries a cancel memo.
        let trustSetWithCancelMemo = makeTrustSetPayload(memo: cancelMemo)
        XCTAssertEqual(
            TransactionHeroResolver.hero(on: .keysignDone, for: trustSetWithCancelMemo),
            RippleTrustSetPresentation.hero(for: trustSetWithCancelMemo)
        )
        XCTAssertNotNil(TransactionHeroResolver.hero(on: .keysignDone, for: trustSetWithCancelMemo))

        // ⚠️ The co-signer's Verify never asked the TrustSet provider, and still
        // doesn't — the same payload resolves as a cancel there.
        XCTAssertEqual(
            TransactionHeroResolver.hero(on: .keysignConfirm, for: trustSetWithCancelMemo),
            LimitOrderCancelPresentation.hero(forSignedMemo: cancelMemo)
        )
    }

    // MARK: - What each screen resolves

    func testTheFunctionCallVerifyResolvesTheWithdrawalHero() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let transaction = try makeTCYWithdrawal()
        let hero = try XCTUnwrap(TransactionHeroResolver.hero(on: .functionCallVerify, for: transaction))
        XCTAssertEqual(hero, FunctionTransactionPresentation.hero(for: transaction))
    }

    func testTheFunctionCallVerifyResolvesTheCancelHero() {
        let transaction = makeCancelTransaction()
        let hero = TransactionHeroResolver.hero(on: .functionCallVerify, for: transaction)
        XCTAssertEqual(hero, LimitOrderCancelPresentation.hero(for: transaction))
        XCTAssertNotNil(hero)
    }

    /// ⚠️ The initiator's Done screen still names no withdrawal.
    ///
    /// The function-call flow's done screen IS `SendDoneScreen`, and the same
    /// transaction arrives there carrying both `functionKind` and
    /// `withdrawDisplayAmount`. Admitting the function-transaction provider would
    /// therefore put a hero on a receipt that has none today — a change worth
    /// making on its own terms, and not what a refactor may do.
    func testTheDoneScreenStillNamesNoWithdrawal() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let transaction = try makeTCYWithdrawal()
        XCTAssertNotNil(transaction.withdrawDisplayAmount)
        XCTAssertNotNil(transaction.functionKind)
        XCTAssertNil(TransactionHeroResolver.hero(on: .sendDone, for: transaction))
    }

    /// A co-signing device holds only the payload, so the memo is the whole story —
    /// the same discriminator THORChain reads.
    func testACoSignerResolvesACancelFromItsMemoAlone() {
        let hero = TransactionHeroResolver.hero(on: .keysignConfirm, for: makePayload(memo: cancelMemo))
        XCTAssertEqual(hero, LimitOrderCancelPresentation.hero(forSignedMemo: cancelMemo))
        XCTAssertNotNil(hero)
    }

    func testACoSignersVerifyResolvesAPlacementFromItsMemoAlone() {
        let payload = makePayload(memo: placementMemo)
        let hero = TransactionHeroResolver.hero(on: .keysignConfirm, for: payload)
        XCTAssertEqual(
            hero,
            LimitOrderPlacementPresentation.hero(
                memo: placementMemo,
                display: LimitOrderPlacementPresentation.display(for: payload)
            )
        )
        XCTAssertNotNil(hero)
    }

    /// The co-signer's DONE screen never showed a placement hero — it falls back to
    /// the simulation-derived one — and still doesn't.
    func testACoSignersDoneStillShowsNoPlacementHero() {
        XCTAssertNil(TransactionHeroResolver.hero(on: .keysignDone, for: makePayload(memo: placementMemo)))
    }

    /// Every ordinary transaction keeps the presentation it already had, on every
    /// surface. `nil` is the caller's signal to fall through.
    func testAnOrdinaryTransactionResolvesNoHeroAnywhere() {
        let transaction = SendTransaction.empty(coin: makeRune(), vault: .example)
        let payload = makePayload(memo: nil)

        for surface in TransactionHeroSurface.allCases {
            XCTAssertNil(TransactionHeroResolver.hero(on: surface, for: transaction), "surface \(surface)")
            XCTAssertNil(TransactionHeroResolver.hero(on: surface, for: payload), "surface \(surface)")
        }
    }

    /// The co-signer screens render before a payload arrives, and a missing payload
    /// has to read as "nothing to say" rather than trap.
    func testAMissingPayloadResolvesNothing() {
        let absent: KeysignPayload? = nil
        for surface in TransactionHeroSurface.allCases {
            XCTAssertNil(TransactionHeroResolver.hero(on: surface, for: absent), "surface \(surface)")
        }
    }

    // MARK: - Fixtures

    private func makeTCYCoin() -> Coin {
        Coin(
            asset: TokensStore.tcy,
            address: "thor1fixturetcyvaultaddress00000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func makeRune() -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
    }

    private func makeTCYWithdrawal() throws -> SendTransaction {
        let vault = TestStore.makeVault()
        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: vault,
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.amountField.value = "1002.73"
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true

        return try XCTUnwrap(viewModel.transactionBuilder).buildSendTransaction(vault: vault)
    }

    /// An XRPL coin whose token id parses, so the TrustSet presentation can
    /// render terms rather than refusing.
    private func makeIssuedCurrencyCoin() -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .ripple,
                ticker: "USD",
                logo: .empty,
                decimals: RippleIssuedCurrency.issuedCurrencyDecimals,
                priceProviderId: .empty,
                contractAddress: "USD.\(Self.issuer)",
                isNativeToken: false
            ),
            address: Self.account,
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
    }

    /// ⚠️ Constructible, not emitted: the withdrawal field and the cancel context
    /// are independent on `SendTransaction`, and this is what the resolver has to
    /// answer if a builder ever sets both.
    private func makeTCYWithdrawalAlsoCarryingACancel() throws -> SendTransaction {
        let withdrawal = try makeTCYWithdrawal()
        return makeTransaction(
            coin: withdrawal.coin,
            amount: withdrawal.amount,
            transactionType: withdrawal.transactionType,
            limitCancelContext: makeCancelContext(),
            withdrawDisplayAmount: withdrawal.withdrawDisplayAmount,
            functionKind: withdrawal.functionKind
        )
    }

    /// The same overlap on the other side: a TrustSet that also carries a cancel
    /// context.
    private func makeTrustSetTransactionAlsoCarryingACancel() -> SendTransaction {
        makeTransaction(
            coin: makeIssuedCurrencyCoin(),
            amount: "1.5",
            transactionType: .rippleTrustSet,
            limitCancelContext: makeCancelContext(),
            withdrawDisplayAmount: nil,
            functionKind: nil
        )
    }

    private func makeCancelContext() -> LimitOrderCancelRequest {
        LimitOrderCancelRequest(
            orderId: "order-1",
            inboundTxHash: "ABC123",
            memo: cancelMemo,
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            sourceChainRawValue: Chain.thorChain.rawValue,
            duplicateRestingOrderCount: 0
        )
    }

    private func makeTransaction(
        coin: Coin,
        amount: String,
        transactionType: VSTransactionType,
        limitCancelContext: LimitOrderCancelRequest?,
        withdrawDisplayAmount: Decimal?,
        functionKind: FunctionTransactionKind?
    ) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: cancelMemo,
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: transactionType,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            limitCancelContext: limitCancelContext,
            withdrawDisplayAmount: withdrawDisplayAmount,
            functionKind: functionKind
        )
    }

    private func makeTrustSetPayload(memo: String? = nil) -> KeysignPayload {
        KeysignPayload(
            coin: makeIssuedCurrencyCoin(),
            toAddress: Self.issuer,
            toAmount: BigInt("1500000000000000"),
            chainSpecific: .Ripple(
                sequence: 1,
                gas: 10,
                lastLedgerSequence: 100,
                transactionType: VSTransactionType.rippleTrustSet.rawValue
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
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
            signData: nil
        )
    }

    private func makeCancelTransaction() -> SendTransaction {
        let coin = makeRune()
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: "0",
            amountInFiat: "",
            memo: cancelMemo,
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
            limitCancelContext: LimitOrderCancelRequest(
                orderId: "order-1",
                inboundTxHash: "ABC123",
                memo: cancelMemo,
                sourceAsset: "THOR.RUNE",
                targetAsset: "BTC.BTC",
                sourceChainRawValue: Chain.thorChain.rawValue,
                duplicateRestingOrderCount: 0
            )
        )
    }

    private func makePayload(memo: String?) -> KeysignPayload {
        KeysignPayload(
            coin: .example,
            toAddress: "thor1to",
            toAmount: BigInt(1000),
            chainSpecific: .THORChain(
                accountNumber: 1,
                sequence: 1,
                fee: 0,
                isDeposit: true,
                transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
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
            signData: nil
        )
    }
}
