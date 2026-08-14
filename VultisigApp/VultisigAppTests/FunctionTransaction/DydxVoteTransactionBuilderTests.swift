//
//  DydxVoteTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the dYdX governance vote transaction. The memo is the whole
//  instruction — `DYDX_VOTE:<option>:<proposalID>` is what the ballot is read
//  out of — so a wrong token in it is a vote cast on something other than what
//  the user picked.
//
//  Carries the golden fixtures from the deleted `FunctionCallVoteTests` and
//  `testVoteParity`, which captured the legacy sub-model verbatim.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class DydxVoteTransactionBuilderTests: XCTestCase {

    private static func makeDydxCoin() -> Coin {
        FunctionActionFixture.makeCoin(.dydx, ticker: "DYDX", decimals: 18, isNative: true)
    }

    private static func makeBuilder(
        option: TW_Cosmos_Proto_Message.VoteOption,
        proposalID: UInt64,
        coin: Coin? = nil
    ) -> DydxVoteTransactionBuilder {
        DydxVoteTransactionBuilder(
            coin: coin ?? makeDydxCoin(),
            option: option,
            proposalID: proposalID
        )
    }

    // MARK: - Memo, per option value

    /// The pin the issue asks for: the memo for **every** option value,
    /// including the one the form refuses to submit. The builder is total on
    /// purpose — keeping `.unspecified` renderable here is what lets this test
    /// state the encoding completely, while
    /// `DydxVoteTransactionViewModelTests` pins that no form can produce it.
    ///
    /// Note the spaces in `No with Veto`: the legacy memo carried them and this
    /// one must too, or the ballot no longer parses to the option picked.
    func testMemoRendersEveryOptionExactlyAsLegacyDid() {
        let expected: [(TW_Cosmos_Proto_Message.VoteOption, String)] = [
            (.unspecified, "DYDX_VOTE:Unspecified:42"),
            (.yes, "DYDX_VOTE:Yes:42"),
            (.abstain, "DYDX_VOTE:Abstain:42"),
            (.no, "DYDX_VOTE:No:42"),
            (.noWithVeto, "DYDX_VOTE:No with Veto:42")
        ]

        for (option, memo) in expected {
            XCTAssertEqual(Self.makeBuilder(option: option, proposalID: 42).memo, memo)
        }
    }

    /// Guards the premise of the test above rather than asserting it in prose:
    /// the memo token is a literal in `DydxVoteOption` precisely so a future
    /// localization of the display-side `description` cannot change what is
    /// signed — but today the two must still agree, or this migration changed
    /// the memo.
    func testMemoTokensStillMatchTheLegacyDescriptionTheyWereCopiedFrom() {
        for option in TW_Cosmos_Proto_Message.VoteOption.allCases {
            XCTAssertEqual(
                DydxVoteOption.memoValue(for: option),
                option.description,
                "\(option) memo token drifted from the legacy source it was pinned to"
            )
        }
    }

    /// Pin: the deleted `testToStringMatchesLegacyMemo`.
    func testMemoMatchesTheLegacyFixture() {
        XCTAssertEqual(Self.makeBuilder(option: .yes, proposalID: 42).memo, "DYDX_VOTE:Yes:42")
    }

    /// A proposal ID is rendered as a plain decimal integer, never grouped and
    /// never abbreviated — the string is what identifies the proposal.
    func testProposalIDIsRenderedAsPlainDigits() {
        XCTAssertEqual(Self.makeBuilder(option: .yes, proposalID: 1).memo, "DYDX_VOTE:Yes:1")
        XCTAssertEqual(Self.makeBuilder(option: .yes, proposalID: 1_234_567).memo, "DYDX_VOTE:Yes:1234567")
        XCTAssertEqual(
            Self.makeBuilder(option: .yes, proposalID: UInt64.max).memo,
            "DYDX_VOTE:Yes:18446744073709551615"
        )
    }

    // MARK: - Attached amount (fund safety)

    /// A vote moves no value: the ballot rides the memo and the deposit is
    /// empty. `SendTransaction.amountInRaw` reads this string as a human
    /// decimal and multiplies by 10^decimals — DYDX has 18 — so a non-zero
    /// default here would attach 10¹⁸ base units to a transaction with no
    /// return path.
    func testAttachedAmountIsZeroForEveryOption() {
        for option in TW_Cosmos_Proto_Message.VoteOption.allCases {
            XCTAssertEqual(Self.makeBuilder(option: option, proposalID: 1).amount, "0")
        }
        XCTAssertFalse(Self.makeBuilder(option: .yes, proposalID: 1).sendMaxAmount)
    }

    // MARK: - Memo dictionary (golden fixture)

    /// Pin: the deleted `testToDictionaryMatchesLegacyKeys` — exactly these
    /// three keys, with the option in its memo form.
    func testMemoDictionaryMatchesTheLegacyKeys() {
        let dict = Self.makeBuilder(option: .no, proposalID: 7).memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["VoteDescription"], "No")
        XCTAssertEqual(dict["ProposalId"], "7")
        XCTAssertEqual(dict["memo"], "DYDX_VOTE:No:7")
        XCTAssertEqual(dict.count, 3)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the deleted `testToSendTransactionMemoMatchesLegacy` and
    /// `testVoteParity`, which between them captured the memo, the transaction
    /// type, the empty recipient and the zero amount.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let coin = Self.makeDydxCoin()
        let vault = FunctionActionFixture.makeVault(coins: [coin])
        let builder = Self.makeBuilder(option: .yes, proposalID: 42, coin: coin)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "DYDX_VOTE:Yes:42")
        XCTAssertEqual(tx.transactionType, .vote)
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.coin.ticker, "DYDX")
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertEqual(tx.memoFunctionDictionary["VoteDescription"], "Yes")
        XCTAssertEqual(tx.memoFunctionDictionary["ProposalId"], "42")
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "DYDX_VOTE:Yes:42")
        // Builders never take gas; `FunctionTransactionScreen.onVerify` fetches
        // it before the verify screen. The legacy sub-model took it as a
        // parameter.
        XCTAssertEqual(tx.gas, .zero)
    }

    /// A vote is not a staking operation and carries no staking payload — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder(option: .yes, proposalID: 1)
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }

    // MARK: - The offered ballot

    /// The defect this migration fixes, at the catalog layer: `.unspecified` is
    /// the proto's zero value, the chain rejects a ballot carrying it, and the
    /// legacy dropdown offered it because it listed `allCases`.
    func testUnspecifiedIsNotOffered() {
        XCTAssertFalse(DydxVoteOption.selectable.contains(.unspecified))
        XCTAssertFalse(DydxVoteOption.isSubmittable(.unspecified))
        XCTAssertNil(DydxVoteOption.option(forMemoValue: "Unspecified"))
    }

    /// And everything else is: the offered set is `allCases` minus the
    /// unsubmittable ones, so a protobuf update that adds a real option shows
    /// up here instead of being silently dropped.
    func testEveryOtherKnownOptionIsOffered() {
        let expected = TW_Cosmos_Proto_Message.VoteOption.allCases.filter { $0 != .unspecified }
        XCTAssertEqual(DydxVoteOption.selectable, expected)
        XCTAssertEqual(DydxVoteOption.selectable, [.yes, .abstain, .no, .noWithVeto])
    }

    /// Every offered option round-trips through its memo token, which is what
    /// the form's option validator relies on.
    func testEveryOfferedOptionRoundTripsThroughItsMemoToken() {
        for option in DydxVoteOption.selectable {
            XCTAssertEqual(DydxVoteOption.option(forMemoValue: DydxVoteOption.memoValue(for: option)), option)
            XCTAssertFalse(DydxVoteOption.displayTitle(for: option).isEmpty)
        }
    }

    /// An unrecognized option — one this build's protobuf does not know — is
    /// never submittable: there is no memo token that names it to the chain.
    func testUnrecognizedOptionsAreNotSubmittable() {
        XCTAssertFalse(DydxVoteOption.isSubmittable(.UNRECOGNIZED(99)))
        XCTAssertFalse(DydxVoteOption.selectable.contains(.UNRECOGNIZED(99)))
    }
}
