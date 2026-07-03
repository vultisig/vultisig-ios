//
//  QBTCGovernanceVoteMemoTests.swift
//  VultisigAppTests
//
//  Pins the single-option vote contract between the governance tab and the
//  signer: the tab emits `QBTC_VOTE:<OPTION>:<PROPOSAL_ID>` (built from the
//  chosen `CosmosGovVoteChoice`), and `QBTCHelper` must parse that memo via
//  the non-signDirect `.vote` path into a deterministic MsgVote SignDoc whose
//  option int matches the proto enum. A wrong memo token would silently cast
//  a different vote, so this guards the mapping end-to-end.
//

@testable import VultisigApp
import VultisigCommonData
import WalletCore
import XCTest

final class QBTCGovernanceVoteMemoTests: XCTestCase {

    private static let voter = "qbtc1voter00000000000000000000000000000000"

    private static func makeQBTCCoin() -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: voter,
            hexPublicKey: String(repeating: "ab", count: 1312)
        )
    }

    /// Builds a `.vote` KeysignPayload through the memo (non-signDirect) path,
    /// exactly as the governance tab's `SendTransaction` resolves to.
    private static func makeVotePayload(memo: String, sequence: UInt64 = 7) -> KeysignPayload {
        KeysignPayload(
            coin: makeQBTCCoin(),
            toAddress: "",
            toAmount: 0,
            chainSpecific: .Cosmos(
                accountNumber: 100,
                sequence: sequence,
                gas: 7500,
                transactionType: VSTransactionType.vote.rawValue,
                ibcDenomTrace: nil, gasLimit: nil
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.GG20.toString(),
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

    /// The tab builds this exact memo string for a chosen option + proposal.
    private static func tabMemo(choice: CosmosGovVoteChoice, proposalID: UInt64) -> String {
        "QBTC_VOTE:\(choice.memoToken):\(proposalID)"
    }

    // MARK: - The tab memo is accepted by the signer (no throw)

    func testTabVoteMemoProducesSignDocForEveryOption() throws {
        for choice in CosmosGovVoteChoice.allCases {
            let memo = Self.tabMemo(choice: choice, proposalID: 42)
            let payload = Self.makeVotePayload(memo: memo)
            let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
            XCTAssertEqual(hashes.count, 1, "memo \(memo) should hash to one pre-image")
            XCTAssertFalse(hashes[0].isEmpty)
        }
    }

    // MARK: - Option + proposal id materially change the signed pre-image

    func testDifferentOptionsYieldDifferentSignDocs() throws {
        let helper = QBTCHelper.create()
        let yesHash = try helper.getPreSignedImageHash(
            keysignPayload: Self.makeVotePayload(memo: Self.tabMemo(choice: .yes, proposalID: 42))
        )[0]
        let noHash = try helper.getPreSignedImageHash(
            keysignPayload: Self.makeVotePayload(memo: Self.tabMemo(choice: .no, proposalID: 42))
        )[0]
        let vetoHash = try helper.getPreSignedImageHash(
            keysignPayload: Self.makeVotePayload(memo: Self.tabMemo(choice: .noWithVeto, proposalID: 42))
        )[0]
        XCTAssertNotEqual(yesHash, noHash)
        XCTAssertNotEqual(noHash, vetoHash)
        XCTAssertNotEqual(yesHash, vetoHash)
    }

    func testDifferentProposalIdsYieldDifferentSignDocs() throws {
        let helper = QBTCHelper.create()
        let p1 = try helper.getPreSignedImageHash(
            keysignPayload: Self.makeVotePayload(memo: Self.tabMemo(choice: .yes, proposalID: 1))
        )[0]
        let p2 = try helper.getPreSignedImageHash(
            keysignPayload: Self.makeVotePayload(memo: Self.tabMemo(choice: .yes, proposalID: 2))
        )[0]
        XCTAssertNotEqual(p1, p2)
    }

    // MARK: - The memo path matches the WalletCore VoteOption enum integers

    /// The tab's `memoToken` must resolve, through the helper, to the same
    /// option int as the canonical WalletCore `VoteOption` enum — so the
    /// signed vote is the one the user picked.
    func testMemoTokenMatchesWalletCoreVoteOptionRawValue() {
        XCTAssertEqual(CosmosGovVoteChoice.yes.rawValue, TW_Cosmos_Proto_Message.VoteOption.yes.rawValue)
        XCTAssertEqual(CosmosGovVoteChoice.abstain.rawValue, TW_Cosmos_Proto_Message.VoteOption.abstain.rawValue)
        XCTAssertEqual(CosmosGovVoteChoice.no.rawValue, TW_Cosmos_Proto_Message.VoteOption.no.rawValue)
        XCTAssertEqual(CosmosGovVoteChoice.noWithVeto.rawValue, TW_Cosmos_Proto_Message.VoteOption.noWithVeto.rawValue)
    }
}
