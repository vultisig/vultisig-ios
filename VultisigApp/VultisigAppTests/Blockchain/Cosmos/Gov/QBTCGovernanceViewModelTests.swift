//
//  QBTCGovernanceViewModelTests.swift
//  VultisigAppTests
//
//  Behaviour coverage for the QBTC governance view-model: active/past
//  split, tally resolution (live `/tally` for active, embedded
//  `final_tally_result` for past), my-vote mapping, empty + error states.
//  Backed by an in-memory stub gov service — no network.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCGovernanceViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func proposal(
        id: UInt64,
        status: CosmosGovProposalStatus,
        finalTally: CosmosGovTallyResult = .zero
    ) -> CosmosGovProposal {
        CosmosGovProposal(
            id: id,
            title: "P\(id)",
            summary: "S\(id)",
            status: status,
            messageTypes: ["/qbtc.qbtc.v1.MsgGovClaimUTXO"],
            finalTally: finalTally,
            submitTime: nil,
            votingStartTime: nil,
            votingEndTime: Date().addingTimeInterval(3600),
            depositEndTime: nil,
            expedited: false,
            failedReason: ""
        )
    }

    // MARK: - Split + ordering

    func testRefreshSplitsActiveAndPastNewestFirst() async {
        let stub = StubGovService(proposals: [
            proposal(id: 1, status: .passed),
            proposal(id: 5, status: .votingPeriod),
            proposal(id: 3, status: .rejected),
            proposal(id: 7, status: .votingPeriod)
        ])
        let viewModel = QBTCGovernanceViewModel(service: stub)

        await viewModel.refresh(voterAddress: nil)

        XCTAssertEqual(viewModel.activeProposals.map(\.id), [7, 5])
        XCTAssertEqual(viewModel.pastProposals.map(\.id), [3, 1])
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertFalse(viewModel.loadFailed)
    }

    // MARK: - Tally resolution

    func testActiveProposalUsesLiveTallyPastUsesFinalTally() async {
        let pastTally = CosmosGovTallyResult(yes: 100, abstain: 0, no: 0, noWithVeto: 0)
        let liveTally = CosmosGovTallyResult(yes: 7, abstain: 1, no: 2, noWithVeto: 0)
        let stub = StubGovService(
            proposals: [
                proposal(id: 9, status: .votingPeriod),
                proposal(id: 2, status: .passed, finalTally: pastTally)
            ],
            tallies: [9: liveTally]
        )
        let viewModel = QBTCGovernanceViewModel(service: stub)

        await viewModel.refresh(voterAddress: nil)

        // Active proposal #9 picks up the live tally.
        XCTAssertEqual(viewModel.tally(for: viewModel.activeProposals[0]), liveTally)
        // Past proposal #2 falls back to its embedded final tally (no /tally call).
        XCTAssertEqual(viewModel.tally(for: viewModel.pastProposals[0]), pastTally)
    }

    func testTallyFallsBackToFinalWhenLiveTallyFails() async {
        let final = CosmosGovTallyResult(yes: 50, abstain: 0, no: 0, noWithVeto: 0)
        let stub = StubGovService(
            proposals: [proposal(id: 4, status: .votingPeriod, finalTally: final)],
            tallyError: true
        )
        let viewModel = QBTCGovernanceViewModel(service: stub)

        await viewModel.refresh(voterAddress: nil)

        // Live tally fetch threw; the proposal still renders its embedded tally.
        XCTAssertEqual(viewModel.tally(for: viewModel.activeProposals[0]), final)
        // A failed tally must NOT fail the whole load.
        XCTAssertFalse(viewModel.loadFailed)
    }

    // MARK: - My vote

    func testMyVoteResolvedWhenVoterProvided() async {
        let vote = CosmosGovVote(
            proposalID: 7,
            voter: "qbtc1me",
            options: [CosmosGovVoteOption(option: .yes, weight: 1)]
        )
        let stub = StubGovService(
            proposals: [proposal(id: 7, status: .votingPeriod)],
            votes: [7: vote]
        )
        let viewModel = QBTCGovernanceViewModel(service: stub)

        await viewModel.refresh(voterAddress: "qbtc1me")

        XCTAssertEqual(viewModel.myVote(for: viewModel.activeProposals[0])?.primaryChoice, .yes)
    }

    func testMyVoteSkippedWhenNoVoterAddress() async {
        let stub = StubGovService(
            proposals: [proposal(id: 7, status: .votingPeriod)],
            votes: [7: CosmosGovVote(proposalID: 7, voter: "x", options: [])]
        )
        let viewModel = QBTCGovernanceViewModel(service: stub)

        await viewModel.refresh(voterAddress: nil)

        XCTAssertNil(viewModel.myVote(for: viewModel.activeProposals[0]))
    }

    // MARK: - Empty + error states

    func testEmptyStateWhenNoProposals() async {
        let viewModel = QBTCGovernanceViewModel(service: StubGovService(proposals: []))
        await viewModel.refresh(voterAddress: nil)
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testLoadFailedWhenProposalsFetchThrows() async {
        let viewModel = QBTCGovernanceViewModel(service: StubGovService(proposalsError: true))
        await viewModel.refresh(voterAddress: nil)
        XCTAssertTrue(viewModel.loadFailed)
        XCTAssertTrue(viewModel.activeProposals.isEmpty)
    }
}

// MARK: - Stub service

private struct StubGovServiceError: Error {}

private final class StubGovService: QBTCGovServiceProtocol, @unchecked Sendable {
    let proposals: [CosmosGovProposal]
    let tallies: [UInt64: CosmosGovTallyResult]
    let votes: [UInt64: CosmosGovVote]
    let proposalsError: Bool
    let tallyError: Bool

    init(
        proposals: [CosmosGovProposal] = [],
        tallies: [UInt64: CosmosGovTallyResult] = [:],
        votes: [UInt64: CosmosGovVote] = [:],
        proposalsError: Bool = false,
        tallyError: Bool = false
    ) {
        self.proposals = proposals
        self.tallies = tallies
        self.votes = votes
        self.proposalsError = proposalsError
        self.tallyError = tallyError
    }

    // swiftlint:disable:next async_without_await unused_parameter
    func fetchProposals(status: CosmosGovProposalStatus?) async throws -> [CosmosGovProposal] {
        if proposalsError { throw StubGovServiceError() }
        return proposals
    }

    // swiftlint:disable:next async_without_await
    func fetchTally(id: UInt64) async throws -> CosmosGovTallyResult {
        if tallyError { throw StubGovServiceError() }
        return tallies[id] ?? .zero
    }

    // swiftlint:disable:next async_without_await unused_parameter
    func fetchMyVote(id: UInt64, voter: String) async throws -> CosmosGovVote? {
        votes[id]
    }

    // swiftlint:disable:next async_without_await
    func fetchGovParams() async throws -> CosmosGovParams {
        CosmosGovParams(votingPeriodSeconds: 172_800, quorum: nil, threshold: nil, vetoThreshold: nil)
    }
}

// MARK: - Presentation helpers

final class QBTCGovernancePresentationTests: XCTestCase {
    func testCountdownFormatsTwoUnits() {
        let now = Date(timeIntervalSince1970: 0)
        let end = now.addingTimeInterval((26 * 3600) + (15 * 60)) // 1d 2h 15m
        let text = QBTCGovernanceFormat.votingCountdown(endTime: end, now: now)
        XCTAssertEqual(text, String(format: "governanceVotingEndsIn".localized, "1d 2h"))
    }

    func testCountdownEndedWhenPast() {
        let now = Date(timeIntervalSince1970: 1000)
        let end = now.addingTimeInterval(-60)
        XCTAssertEqual(QBTCGovernanceFormat.votingCountdown(endTime: end, now: now), "governanceVotingEnded".localized)
    }

    func testCountdownNilWhenNoEnd() {
        XCTAssertNil(QBTCGovernanceFormat.votingCountdown(endTime: nil))
    }

    func testShortDurationUnits() {
        XCTAssertEqual(QBTCGovernanceFormat.shortDuration(0), "<1m")
        XCTAssertEqual(QBTCGovernanceFormat.shortDuration(5 * 60), "5m")
        XCTAssertEqual(QBTCGovernanceFormat.shortDuration((3 * 3600) + (4 * 60)), "3h 4m")
        XCTAssertEqual(QBTCGovernanceFormat.shortDuration((2 * 86400) + (5 * 3600)), "2d 5h")
    }

    func testMessageShortLabelStripsTypeURL() {
        XCTAssertEqual(
            QBTCGovernanceFormat.messageShortLabel("/qbtc.qbtc.v1.MsgGovClaimUTXO"),
            "MsgGovClaimUTXO"
        )
        XCTAssertEqual(
            QBTCGovernanceFormat.messageShortLabel("/cosmos.gov.v1.MsgExecLegacyContent"),
            "MsgExecLegacyContent"
        )
        // No dot to split on — falls back to the full string.
        XCTAssertEqual(QBTCGovernanceFormat.messageShortLabel("weird"), "weird")
    }
}
