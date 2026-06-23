//
//  CosmosGovDTOTests.swift
//  VultisigAppTests
//
//  Decode coverage for the QBTC x/gov v1 LCD DTOs. The JSON literals are
//  verbatim copies of the live qbtc-rpc proxy responses captured during
//  scoping (proposal #1, its tally, the voting params) plus the standard
//  cosmos-sdk vote / votingless shapes — so these double as a wire-format
//  contract for the proposals tab.
//

@testable import VultisigApp
import XCTest

final class CosmosGovDTOTests: XCTestCase {

    // MARK: - Proposals list (real qbtc-testnet shape)

    /// The single live proposal: PASSED, wrapping a `/qbtc.qbtc.v1.MsgGovClaimUTXO`.
    private static let proposalsJSON = """
    {
      "proposals": [{
        "id": "1",
        "messages": [{
          "@type": "/qbtc.qbtc.v1.MsgGovClaimUTXO",
          "authority": "qbtc10d07y265gmmuvt4z0w9aw880jnsr700j89jqe8",
          "utxos": [{ "txid": "0e3e", "vout": 0 }]
        }],
        "status": "PROPOSAL_STATUS_PASSED",
        "final_tally_result": {
          "yes_count": "1800000000", "abstain_count": "0",
          "no_count": "0", "no_with_veto_count": "0"
        },
        "submit_time": "2026-05-07T09:41:49.219457Z",
        "deposit_end_time": "2026-05-09T09:41:49.219457Z",
        "total_deposit": [{ "denom": "qbtc", "amount": "900000000" }],
        "voting_start_time": "2026-05-07T09:41:49.219457Z",
        "voting_end_time": "2026-05-09T09:41:49.219457Z",
        "metadata": "", "title": "Claim UTXO to reserve", "summary": "Claim UTXO to reserve",
        "proposer": "qbtc13vp28kmfx3kznmukw20ev8gfk8tyyt42gcqayz",
        "expedited": false, "failed_reason": ""
      }],
      "pagination": { "next_key": null, "total": "0" }
    }
    """

    func testProposalsListDecodesLiveShape() throws {
        let response = try JSONDecoder().decode(
            CosmosGovProposalsResponse.self,
            from: Data(Self.proposalsJSON.utf8)
        )
        let proposals = response.toProposals()
        XCTAssertEqual(proposals.count, 1)

        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal.id, 1)
        XCTAssertEqual(proposal.title, "Claim UTXO to reserve")
        XCTAssertEqual(proposal.summary, "Claim UTXO to reserve")
        XCTAssertEqual(proposal.status, .passed)
        XCTAssertFalse(proposal.status.isActive)
        XCTAssertEqual(proposal.messageTypes, ["/qbtc.qbtc.v1.MsgGovClaimUTXO"])
        XCTAssertEqual(proposal.finalTally.yes, 1_800_000_000)
        XCTAssertEqual(proposal.finalTally.total, 1_800_000_000)
        XCTAssertFalse(proposal.expedited)
        XCTAssertNotNil(proposal.votingStartTime)
        XCTAssertNotNil(proposal.votingEndTime)

        // next_key null at the end of the list.
        XCTAssertNil(response.pagination?.nextKey)
    }

    func testProposalWithUnparseableIdIsDropped() throws {
        let json = """
        { "proposals": [
          { "id": "not-a-number", "status": "PROPOSAL_STATUS_PASSED" },
          { "id": "7", "status": "PROPOSAL_STATUS_VOTING_PERIOD" }
        ], "pagination": { "next_key": null } }
        """
        let response = try JSONDecoder().decode(
            CosmosGovProposalsResponse.self,
            from: Data(json.utf8)
        )
        let proposals = response.toProposals()
        XCTAssertEqual(proposals.map(\.id), [7])
        XCTAssertEqual(proposals.first?.status, .votingPeriod)
        XCTAssertTrue(proposals.first?.status.isActive == true)
    }

    func testUnknownStatusMapsToUnspecifiedWithoutFailingDecode() throws {
        let json = """
        { "proposals": [{ "id": "3", "status": "PROPOSAL_STATUS_SOMETHING_NEW" }] }
        """
        let response = try JSONDecoder().decode(
            CosmosGovProposalsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.toProposals().first?.status, .unspecified)
    }

    func testMissingStatusDecodesAndMapsToUnspecified() throws {
        // A missing/null `status` must not fail decoding before the
        // `.unspecified` fallback runs — only an unparseable `id` drops a
        // proposal.
        let json = """
        { "proposals": [{ "id": "11" }] }
        """
        let response = try JSONDecoder().decode(
            CosmosGovProposalsResponse.self,
            from: Data(json.utf8)
        )
        let proposals = response.toProposals()
        XCTAssertEqual(proposals.map(\.id), [11])
        XCTAssertEqual(proposals.first?.status, .unspecified)
    }

    func testProposalWithoutMessagesDecodesToEmptyTypes() throws {
        let json = """
        { "proposal": { "id": "9", "status": "PROPOSAL_STATUS_REJECTED",
          "title": "T", "summary": "S" } }
        """
        let response = try JSONDecoder().decode(
            CosmosGovProposalResponse.self,
            from: Data(json.utf8)
        )
        let proposal = try XCTUnwrap(response.toProposal())
        XCTAssertEqual(proposal.messageTypes, [])
        XCTAssertEqual(proposal.status, .rejected)
        XCTAssertEqual(proposal.finalTally, .zero)
    }

    // MARK: - Tally (real live shape)

    func testTallyResponseDecodesAndComputesFractions() throws {
        let json = """
        { "tally": { "yes_count": "70", "abstain_count": "10",
          "no_count": "15", "no_with_veto_count": "5" } }
        """
        let tally = try JSONDecoder().decode(
            CosmosGovTallyResponse.self,
            from: Data(json.utf8)
        ).toTally()

        XCTAssertEqual(tally.yes, 70)
        XCTAssertEqual(tally.abstain, 10)
        XCTAssertEqual(tally.no, 15)
        XCTAssertEqual(tally.noWithVeto, 5)
        XCTAssertEqual(tally.total, 100)
        XCTAssertEqual(tally.fraction(of: tally.yes), Decimal(string: "0.7"))
        XCTAssertEqual(tally.fraction(of: tally.noWithVeto), Decimal(string: "0.05"))
    }

    func testTallyFractionIsZeroWhenNoVotes() {
        let tally = CosmosGovTallyResult.zero
        XCTAssertEqual(tally.total, 0)
        XCTAssertEqual(tally.fraction(of: tally.yes), 0)
    }

    // MARK: - My vote

    func testVoteResponseDecodesWeightedOptions() throws {
        let json = """
        { "vote": { "proposal_id": "42", "voter": "qbtc1abc",
          "options": [
            { "option": "VOTE_OPTION_YES", "weight": "0.700000000000000000" },
            { "option": "VOTE_OPTION_ABSTAIN", "weight": "0.300000000000000000" }
          ], "metadata": "" } }
        """
        let vote = try XCTUnwrap(
            try JSONDecoder().decode(CosmosGovVoteResponse.self, from: Data(json.utf8)).toVote()
        )
        XCTAssertEqual(vote.proposalID, 42)
        XCTAssertEqual(vote.voter, "qbtc1abc")
        XCTAssertEqual(vote.options.count, 2)
        // Dominant option (highest weight) drives the "You voted X" badge.
        XCTAssertEqual(vote.primaryChoice, .yes)
    }

    func testVoteResponseDecodesSingleOption() throws {
        let json = """
        { "vote": { "proposal_id": "1", "voter": "qbtc1xyz",
          "options": [{ "option": "VOTE_OPTION_NO_WITH_VETO", "weight": "1.000000000000000000" }] } }
        """
        let vote = try XCTUnwrap(
            try JSONDecoder().decode(CosmosGovVoteResponse.self, from: Data(json.utf8)).toVote()
        )
        XCTAssertEqual(vote.primaryChoice, .noWithVeto)
        XCTAssertEqual(vote.options.first?.weight, Decimal(string: "1.0"))
    }

    func testVoteChoiceWireRoundTrip() {
        XCTAssertEqual(CosmosGovVoteChoice(wire: "VOTE_OPTION_YES"), .yes)
        XCTAssertEqual(CosmosGovVoteChoice(wire: "VOTE_OPTION_ABSTAIN"), .abstain)
        XCTAssertEqual(CosmosGovVoteChoice(wire: "VOTE_OPTION_NO"), .no)
        XCTAssertEqual(CosmosGovVoteChoice(wire: "VOTE_OPTION_NO_WITH_VETO"), .noWithVeto)
        XCTAssertNil(CosmosGovVoteChoice(wire: "VOTE_OPTION_UNSPECIFIED"))
    }

    /// The memo token must map back to the canonical proto enum integer so
    /// the signed MsgVote casts the vote the user actually picked.
    func testVoteChoiceMemoTokensMatchProtoIntegers() {
        XCTAssertEqual(CosmosGovVoteChoice.yes.rawValue, 1)
        XCTAssertEqual(CosmosGovVoteChoice.abstain.rawValue, 2)
        XCTAssertEqual(CosmosGovVoteChoice.no.rawValue, 3)
        XCTAssertEqual(CosmosGovVoteChoice.noWithVeto.rawValue, 4)
        XCTAssertEqual(CosmosGovVoteChoice.yes.memoToken, "YES")
        XCTAssertEqual(CosmosGovVoteChoice.noWithVeto.memoToken, "NO_WITH_VETO")
    }

    // MARK: - Params (real live shape)

    func testParamsResponseDecodesVotingPeriodAndThresholds() throws {
        let json = """
        { "voting_params": { "voting_period": "172800s" },
          "params": {
            "min_deposit": [{ "denom": "qbtc", "amount": "10000000" }],
            "max_deposit_period": "172800s", "voting_period": "172800s",
            "quorum": "0.334000000000000000", "threshold": "0.500000000000000000",
            "veto_threshold": "0.334000000000000000",
            "expedited_voting_period": "86400s", "burn_vote_veto": true } }
        """
        let params = try JSONDecoder().decode(
            CosmosGovParamsResponse.self,
            from: Data(json.utf8)
        ).toParams()

        XCTAssertEqual(params.votingPeriodSeconds, 172_800)
        XCTAssertEqual(params.quorum, Decimal(string: "0.334"))
        XCTAssertEqual(params.threshold, Decimal(string: "0.5"))
        XCTAssertEqual(params.vetoThreshold, Decimal(string: "0.334"))
    }

    func testDurationParserHandlesSecondsSuffixAndRejectsJunk() {
        XCTAssertEqual(CosmosGovParamsResponse.parseDurationSeconds("172800s"), 172_800)
        XCTAssertEqual(CosmosGovParamsResponse.parseDurationSeconds("0s"), 0)
        XCTAssertNil(CosmosGovParamsResponse.parseDurationSeconds("172800"))
        XCTAssertNil(CosmosGovParamsResponse.parseDurationSeconds(""))
        XCTAssertNil(CosmosGovParamsResponse.parseDurationSeconds("abcs"))
    }

    // MARK: - Service status filter helper

    func testStatusFilterMapsDomainStatusToWire() {
        XCTAssertNil(QBTCGovService.statusFilter(for: nil))
        XCTAssertNil(QBTCGovService.statusFilter(for: .unspecified))
        XCTAssertEqual(QBTCGovService.statusFilter(for: .votingPeriod), "PROPOSAL_STATUS_VOTING_PERIOD")
        XCTAssertEqual(QBTCGovService.statusFilter(for: .passed), "PROPOSAL_STATUS_PASSED")
        XCTAssertEqual(QBTCGovService.statusFilter(for: .rejected), "PROPOSAL_STATUS_REJECTED")
        XCTAssertEqual(QBTCGovService.statusFilter(for: .failed), "PROPOSAL_STATUS_FAILED")
        XCTAssertEqual(QBTCGovService.statusFilter(for: .depositPeriod), "PROPOSAL_STATUS_DEPOSIT_PERIOD")
    }

    // MARK: - Service: my-vote 404 → nil (not-voted is not an error)

    func testFetchMyVoteReturnsNilOn404() async throws {
        let service = QBTCGovService(httpClient: GovStubHTTPClient(statusCode: 404, body: ""))
        let vote = try await service.fetchMyVote(id: 1, voter: "qbtc1novote")
        XCTAssertNil(vote)
    }

    func testFetchMyVoteDecodesOn200() async throws {
        let body = """
        { "vote": { "proposal_id": "1", "voter": "qbtc1voted",
          "options": [{ "option": "VOTE_OPTION_YES", "weight": "1.000000000000000000" }] } }
        """
        let service = QBTCGovService(httpClient: GovStubHTTPClient(statusCode: 200, body: body))
        let vote = try await service.fetchMyVote(id: 1, voter: "qbtc1voted")
        XCTAssertEqual(vote?.primaryChoice, .yes)
    }
}

/// Minimal `HTTPClientProtocol` stub returning a fixed status + body, used to
/// exercise the service's 404 handling without a real network call.
private final class GovStubHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let statusCode: Int
    private let body: String

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://example.test")!
        // swiftlint:disable:next force_unwrapping
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }
}
