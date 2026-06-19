//
//  QBTCGovService.swift
//  VultisigApp
//
//  Read-side service for the QBTC x/gov v1 LCD endpoints backing the
//  governance proposals tab. Goes through the shared `HTTPClient` per the
//  networking rule — the view-model calls only this service.
//
//  Hits `/cosmos/gov/v1/...` on the qbtc-rpc proxy (verified live: the
//  proxy passes the standard cosmos gov paths). The vote *message* the user
//  signs stays at gov v1beta1 (`QBTCHelper`) — only the read path is v1.
//

import Foundation
import OSLog

protocol QBTCGovServiceProtocol: Sendable {
    func fetchProposals(status: CosmosGovProposalStatus?) async throws -> [CosmosGovProposal]
    func fetchProposal(id: UInt64) async throws -> CosmosGovProposal?
    func fetchTally(id: UInt64) async throws -> CosmosGovTallyResult
    func fetchMyVote(id: UInt64, voter: String) async throws -> CosmosGovVote?
    func fetchGovParams() async throws -> CosmosGovParams
}

struct QBTCGovService: QBTCGovServiceProtocol {

    /// Default page size for the proposals list. The tab shows active + a
    /// recent-history window; 100 comfortably covers qbtc-testnet (1
    /// proposal today) without paging. If a real chain ever exceeds this,
    /// the list gains a "load more" off `pagination.next_key`.
    static let defaultProposalLimit = 100

    private let httpClient: HTTPClientProtocol
    private let logger: Logger

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        logger: Logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-gov-service")
    ) {
        self.httpClient = httpClient
        self.logger = logger
    }

    /// Lists proposals, optionally filtered server-side by status. Passing
    /// `nil` returns every proposal (active + past) in one call so the tab
    /// can split them client-side without two round-trips.
    func fetchProposals(status: CosmosGovProposalStatus?) async throws -> [CosmosGovProposal] {
        let response = try await httpClient.request(
            QBTCChainAPI.govProposals(
                status: Self.statusFilter(for: status),
                limit: Self.defaultProposalLimit
            ),
            responseType: CosmosGovProposalsResponse.self
        )
        return response.data.toProposals()
    }

    func fetchProposal(id: UInt64) async throws -> CosmosGovProposal? {
        let response = try await httpClient.request(
            QBTCChainAPI.govProposal(id: id),
            responseType: CosmosGovProposalResponse.self
        )
        return response.data.toProposal()
    }

    func fetchTally(id: UInt64) async throws -> CosmosGovTallyResult {
        let response = try await httpClient.request(
            QBTCChainAPI.govTally(id: id),
            responseType: CosmosGovTallyResponse.self
        )
        return response.data.toTally()
    }

    /// Returns the voter's recorded vote, or `nil` when the LCD answers 404
    /// (the voter hasn't voted on this proposal). The `govVote` endpoint is
    /// configured to accept 404 as a non-error in `QBTCChainAPI`.
    func fetchMyVote(id: UInt64, voter: String) async throws -> CosmosGovVote? {
        let response = try await httpClient.request(QBTCChainAPI.govVote(id: id, voter: voter))
        if response.response.statusCode == 404 {
            return nil
        }
        let decoded = try JSONDecoder().decode(CosmosGovVoteResponse.self, from: response.data)
        return decoded.toVote()
    }

    /// Fetches the gov voting params (voting-period length + thresholds).
    func fetchGovParams() async throws -> CosmosGovParams {
        let response = try await httpClient.request(
            QBTCChainAPI.govParams(type: "voting"),
            responseType: CosmosGovParamsResponse.self
        )
        return response.data.toParams()
    }

    // MARK: - Pure helpers (testable without network)

    /// Maps a domain status to the LCD `proposal_status` filter string, or
    /// `nil` to request every proposal. `.unspecified` is treated as
    /// "no filter".
    static func statusFilter(for status: CosmosGovProposalStatus?) -> String? {
        switch status {
        case .none, .some(.unspecified):
            return nil
        case .some(.depositPeriod):
            return "PROPOSAL_STATUS_DEPOSIT_PERIOD"
        case .some(.votingPeriod):
            return "PROPOSAL_STATUS_VOTING_PERIOD"
        case .some(.passed):
            return "PROPOSAL_STATUS_PASSED"
        case .some(.rejected):
            return "PROPOSAL_STATUS_REJECTED"
        case .some(.failed):
            return "PROPOSAL_STATUS_FAILED"
        }
    }
}
