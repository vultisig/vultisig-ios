//
//  QBTCGovernanceViewModel.swift
//  VultisigApp
//
//  Backs the QBTC governance segment on the DeFi tab. Loads the proposal
//  list once, splits it into active (voting-period) vs past, and resolves
//  the live tally + the user's recorded vote for the proposals on screen.
//  Refresh fires on `.onLoad` and on pull-to-refresh.
//
//  QBTC is the first native Vultisig client with an in-app proposals tab —
//  the closest in-app analog is the Cosmos staking segment
//  (`CosmosStakeDefiViewModel`), whose fan-out + per-call-degrade shape this
//  mirrors.
//

import Foundation
import OSLog

@MainActor
final class QBTCGovernanceViewModel: ObservableObject {
    /// Proposals still in their voting window — votable, shown first.
    @Published private(set) var activeProposals: [CosmosGovProposal] = []
    /// Terminal proposals (passed / rejected / failed) and any in deposit —
    /// the history section.
    @Published private(set) var pastProposals: [CosmosGovProposal] = []
    /// Live tally per proposal id. For active proposals this comes from the
    /// `/tally` endpoint; for past ones the proposal's `final_tally_result`
    /// is used directly and this stays empty.
    @Published private(set) var liveTallies: [UInt64: CosmosGovTallyResult] = [:]
    /// The user's recorded vote per proposal id, when they have voted.
    @Published private(set) var myVotes: [UInt64: CosmosGovVote] = [:]
    @Published private(set) var params: CosmosGovParams?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadFailed: Bool = false

    /// Bech32 address whose votes are highlighted. Set on refresh from the
    /// vault's native QBTC coin.
    private(set) var voterAddress: String?

    private let service: QBTCGovServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "qbtc-governance-vm"
    )

    init(service: QBTCGovServiceProtocol = QBTCGovService()) {
        self.service = service
    }

    /// `true` once a load has completed and produced no proposals at all —
    /// drives the empty state. Distinct from `loadFailed` (a network error).
    var isEmpty: Bool {
        !isLoading && activeProposals.isEmpty && pastProposals.isEmpty
    }

    /// Fetches the full proposal list + gov params, splits active vs past,
    /// then resolves the live tally for active proposals and the user's vote
    /// for every proposal. Per-call failures degrade individually: a failed
    /// tally leaves the proposal showing its embedded `final_tally_result`,
    /// a failed my-vote query just omits the "you voted" badge. The whole
    /// load only flips `loadFailed` when the proposal list itself fails.
    func refresh(voterAddress: String?) async {
        self.voterAddress = voterAddress
        isLoading = true
        defer { isLoading = false }

        async let proposalsTask = fetchProposals()
        async let paramsTask = fetchParams()

        let proposals = await proposalsTask
        params = await paramsTask

        guard let proposals else {
            loadFailed = true
            return
        }
        loadFailed = false

        // Active first (newest id first), then past (newest id first).
        let active = proposals.filter { $0.status.isActive }.sorted { $0.id > $1.id }
        let past = proposals.filter { !$0.status.isActive }.sorted { $0.id > $1.id }
        activeProposals = active
        pastProposals = past

        await resolveTallies(for: active)
        await resolveMyVotes(for: proposals, voterAddress: voterAddress)

        if proposals.isEmpty {
            logger.info("No QBTC governance proposals returned")
        }
    }

    /// The tally to display for a proposal: the live `/tally` when present
    /// (active proposals), otherwise the embedded `final_tally_result`.
    func tally(for proposal: CosmosGovProposal) -> CosmosGovTallyResult {
        liveTallies[proposal.id] ?? proposal.finalTally
    }

    /// The user's recorded vote on a proposal, if any.
    func myVote(for proposal: CosmosGovProposal) -> CosmosGovVote? {
        myVotes[proposal.id]
    }

    // MARK: - Fetch helpers (each degrades independently)

    private func fetchProposals() async -> [CosmosGovProposal]? {
        do {
            return try await service.fetchProposals(status: nil)
        } catch {
            logger.error("Failed to fetch proposals: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchParams() async -> CosmosGovParams? {
        do {
            return try await service.fetchGovParams()
        } catch {
            logger.warning("Failed to fetch gov params: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func resolveTallies(for proposals: [CosmosGovProposal]) async {
        guard !proposals.isEmpty else {
            liveTallies = [:]
            return
        }
        let resolved = await withTaskGroup(of: (UInt64, CosmosGovTallyResult?).self) { group in
            for proposal in proposals {
                group.addTask { [service, logger] in
                    do {
                        return (proposal.id, try await service.fetchTally(id: proposal.id))
                    } catch {
                        logger.warning("Failed to fetch tally for \(proposal.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (proposal.id, nil)
                    }
                }
            }
            var out: [UInt64: CosmosGovTallyResult] = [:]
            for await (id, tally) in group {
                if let tally {
                    out[id] = tally
                }
            }
            return out
        }
        liveTallies = resolved
    }

    private func resolveMyVotes(for proposals: [CosmosGovProposal], voterAddress: String?) async {
        guard let voterAddress, !proposals.isEmpty else {
            myVotes = [:]
            return
        }
        let resolved = await withTaskGroup(of: (UInt64, CosmosGovVote?).self) { group in
            for proposal in proposals {
                group.addTask { [service, logger] in
                    do {
                        return (proposal.id, try await service.fetchMyVote(id: proposal.id, voter: voterAddress))
                    } catch {
                        logger.warning("Failed to fetch my-vote for \(proposal.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (proposal.id, nil)
                    }
                }
            }
            var out: [UInt64: CosmosGovVote] = [:]
            for await (id, vote) in group {
                if let vote {
                    out[id] = vote
                }
            }
            return out
        }
        myVotes = resolved
    }
}
