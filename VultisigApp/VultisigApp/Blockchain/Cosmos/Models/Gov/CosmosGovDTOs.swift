//
//  CosmosGovDTOs.swift
//  VultisigApp
//
//  Read-side DTOs for the Cosmos-SDK x/gov v1 LCD endpoints used by the
//  QBTC governance proposals tab. Shape mirrors the `/cosmos/gov/v1/...`
//  REST responses served by the qbtc-rpc proxy — snake_case on the wire,
//  mapped to camelCase domain value types here via `CodingKeys` + `toX()`
//  mappers, in the same style as `CosmosStakingDTOs`.
//
//  Queried with gov *v1* (richer: `messages[]`, `title`, `summary`,
//  `expedited`, `failed_reason`). The vote *message* stays at gov
//  `v1beta1` — see `QBTCHelper` and the cross-platform byte-equality gate.
//
//  Quantities arrive as JSON strings (uint base units / `cosmos.Dec`),
//  times as RFC3339. Dates reuse the staking `CosmosStakingDateParser`,
//  which already tolerates the fractional + non-fractional gov shapes.
//

import Foundation

// MARK: - Proposal status

/// Lifecycle status of a gov proposal. Decoded from the `PROPOSAL_STATUS_*`
/// string the LCD returns; an unknown/missing value maps to `.unspecified`
/// so a new on-chain status never fails the whole decode.
enum CosmosGovProposalStatus: Equatable, Sendable {
    case unspecified
    case depositPeriod
    case votingPeriod
    case passed
    case rejected
    case failed

    init(wire: String) {
        switch wire {
        case "PROPOSAL_STATUS_DEPOSIT_PERIOD": self = .depositPeriod
        case "PROPOSAL_STATUS_VOTING_PERIOD": self = .votingPeriod
        case "PROPOSAL_STATUS_PASSED": self = .passed
        case "PROPOSAL_STATUS_REJECTED": self = .rejected
        case "PROPOSAL_STATUS_FAILED": self = .failed
        default: self = .unspecified
        }
    }

    /// `true` while the proposal can still be voted on.
    var isActive: Bool { self == .votingPeriod }
}

// MARK: - Tally

/// Vote counts in bond-denom base units. Decoded from both the live
/// `/tally` endpoint (active proposals) and the `final_tally_result` block
/// embedded on a proposal (past ones). Counts are kept as `Decimal` so the
/// view layer can compute per-option percentages without float drift.
struct CosmosGovTallyResult: Equatable, Sendable {
    let yes: Decimal
    let abstain: Decimal
    let no: Decimal
    let noWithVeto: Decimal

    static let zero = CosmosGovTallyResult(yes: 0, abstain: 0, no: 0, noWithVeto: 0)

    /// Sum of all four options. The denominator for the per-option bar.
    var total: Decimal { yes + abstain + no + noWithVeto }

    /// Fraction (0...1) of the total that each option holds. Returns 0 when
    /// no votes have been cast so the bar renders empty rather than NaN.
    func fraction(of count: Decimal) -> Decimal {
        guard total > 0 else { return 0 }
        return count / total
    }
}

/// Wire shape shared by the standalone `/tally` response and the
/// `final_tally_result` field on a proposal.
struct CosmosGovTallyWire: Decodable {
    let yesCount: String
    let abstainCount: String
    let noCount: String
    let noWithVetoCount: String

    enum CodingKeys: String, CodingKey {
        case yesCount = "yes_count"
        case abstainCount = "abstain_count"
        case noCount = "no_count"
        case noWithVetoCount = "no_with_veto_count"
    }

    func toTally() -> CosmosGovTallyResult {
        CosmosGovTallyResult(
            yes: Decimal(string: yesCount) ?? 0,
            abstain: Decimal(string: abstainCount) ?? 0,
            no: Decimal(string: noCount) ?? 0,
            noWithVeto: Decimal(string: noWithVetoCount) ?? 0
        )
    }
}

/// Response envelope for `GET /cosmos/gov/v1/proposals/{id}/tally`.
struct CosmosGovTallyResponse: Decodable {
    let tally: CosmosGovTallyWire

    func toTally() -> CosmosGovTallyResult {
        tally.toTally()
    }
}

// MARK: - Proposal

/// A gov proposal in domain form. `messages` carries the wrapped message
/// type URLs (e.g. `/cosmos.*` or `/qbtc.qbtc.v1.*`) rendered generically by
/// the detail view — proposals can wrap any message type, so nothing here is
/// special-cased per message.
struct CosmosGovProposal: Equatable, Sendable, Identifiable {
    let id: UInt64
    let title: String
    let summary: String
    let status: CosmosGovProposalStatus
    /// Wrapped message type URLs (`@type`), in order. May be empty.
    let messageTypes: [String]
    /// Tally embedded on the proposal (`final_tally_result`). For an active
    /// proposal this is usually all-zero until the live `/tally` is fetched.
    let finalTally: CosmosGovTallyResult
    let submitTime: Date?
    let votingStartTime: Date?
    let votingEndTime: Date?
    let depositEndTime: Date?
    let expedited: Bool
    let failedReason: String
}

/// Wire shape for a single proposal in the v1 list / detail response.
struct CosmosGovProposalWire: Decodable {
    let id: String
    let messages: [WireMessage]?
    let status: String
    let finalTallyResult: CosmosGovTallyWire?
    let submitTime: String?
    let depositEndTime: String?
    let votingStartTime: String?
    let votingEndTime: String?
    let metadata: String?
    let title: String?
    let summary: String?
    let expedited: Bool?
    let failedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case messages
        case status
        case finalTallyResult = "final_tally_result"
        case submitTime = "submit_time"
        case depositEndTime = "deposit_end_time"
        case votingStartTime = "voting_start_time"
        case votingEndTime = "voting_end_time"
        case metadata
        case title
        case summary
        case expedited
        case failedReason = "failed_reason"
    }

    /// Only the `@type` discriminator is decoded — the per-message payload
    /// shape varies by type and the tab renders the type URL generically.
    struct WireMessage: Decodable {
        let type: String

        enum CodingKeys: String, CodingKey {
            case type = "@type"
        }
    }

    /// Maps to the domain proposal. Returns `nil` only when `id` is not a
    /// parseable uint64 — every other field degrades to a safe default so a
    /// single odd proposal never drops the whole list.
    func toProposal() -> CosmosGovProposal? {
        guard let id = UInt64(id) else { return nil }
        return CosmosGovProposal(
            id: id,
            title: title ?? "",
            summary: summary ?? "",
            status: CosmosGovProposalStatus(wire: status),
            messageTypes: (messages ?? []).map(\.type),
            finalTally: finalTallyResult?.toTally() ?? .zero,
            submitTime: submitTime.flatMap(CosmosStakingDateParser.parse),
            votingStartTime: votingStartTime.flatMap(CosmosStakingDateParser.parse),
            votingEndTime: votingEndTime.flatMap(CosmosStakingDateParser.parse),
            depositEndTime: depositEndTime.flatMap(CosmosStakingDateParser.parse),
            expedited: expedited ?? false,
            failedReason: failedReason ?? ""
        )
    }
}

/// Response envelope for `GET /cosmos/gov/v1/proposals[?...]`.
struct CosmosGovProposalsResponse: Decodable {
    let proposals: [CosmosGovProposalWire]
    let pagination: CosmosGovPagination?

    func toProposals() -> [CosmosGovProposal] {
        proposals.compactMap { $0.toProposal() }
    }
}

/// Response envelope for `GET /cosmos/gov/v1/proposals/{id}`.
struct CosmosGovProposalResponse: Decodable {
    let proposal: CosmosGovProposalWire

    func toProposal() -> CosmosGovProposal? {
        proposal.toProposal()
    }
}

/// Standard Cosmos LCD pagination block. `nextKey` is null at the end of the
/// list; `total` is only populated when `pagination.count_total=true`.
struct CosmosGovPagination: Decodable, Equatable {
    let nextKey: String?
    let total: String?

    enum CodingKeys: String, CodingKey {
        case nextKey = "next_key"
        case total
    }
}

// MARK: - My vote

/// A single weighted option in a vote. For a simple (single-option) vote the
/// LCD still returns a one-element array with weight "1.0".
struct CosmosGovVoteOption: Equatable, Sendable {
    /// Option enum string name as returned by the LCD
    /// (`VOTE_OPTION_YES` / `VOTE_OPTION_NO` / …).
    let option: CosmosGovVoteChoice
    /// `cosmos.Dec` weight (0...1). 1.0 for a single-option vote.
    let weight: Decimal
}

/// The user's recorded vote on a proposal.
struct CosmosGovVote: Equatable, Sendable {
    let proposalID: UInt64
    let voter: String
    let options: [CosmosGovVoteOption]

    /// The dominant option (highest weight) — what a "You voted X" badge
    /// shows. For a single-option vote this is the only option.
    var primaryChoice: CosmosGovVoteChoice? {
        options.max(by: { $0.weight < $1.weight })?.option
    }
}

/// The four user-selectable vote choices (excludes UNSPECIFIED). Shared by
/// the vote DTO, the vote sheet, and the memo builder. Raw values match the
/// canonical Cosmos `VoteOption` proto enum integers (YES=1, ABSTAIN=2,
/// NO=3, NO_WITH_VETO=4) — the same ordering `QBTCHelper` signs.
enum CosmosGovVoteChoice: Int, CaseIterable, Equatable, Sendable, Identifiable {
    case yes = 1
    case abstain = 2
    case no = 3
    case noWithVeto = 4

    var id: Int { rawValue }

    /// Decodes the LCD enum-string form (`VOTE_OPTION_*`). `nil` for an
    /// unrecognized / unspecified option.
    init?(wire: String) {
        switch wire {
        case "VOTE_OPTION_YES", "1": self = .yes
        case "VOTE_OPTION_ABSTAIN", "2": self = .abstain
        case "VOTE_OPTION_NO", "3": self = .no
        case "VOTE_OPTION_NO_WITH_VETO", "4": self = .noWithVeto
        default: return nil
        }
    }

    /// Uppercased token used in the `QBTC_VOTE:` / `QBTC_VOTEW:` memo, which
    /// `QBTCHelper.voteOptionValue` maps back to the proto integer.
    var memoToken: String {
        switch self {
        case .yes: return "YES"
        case .abstain: return "ABSTAIN"
        case .no: return "NO"
        case .noWithVeto: return "NO_WITH_VETO"
        }
    }

    /// Localized display title for the option.
    var displayTitle: String {
        switch self {
        case .yes: return "governanceVoteYes".localized
        case .abstain: return "governanceVoteAbstain".localized
        case .no: return "governanceVoteNo".localized
        case .noWithVeto: return "governanceVoteNoWithVeto".localized
        }
    }
}

/// Wire shape for `GET /cosmos/gov/v1/proposals/{id}/votes/{voter}`.
struct CosmosGovVoteResponse: Decodable {
    let vote: WireVote

    struct WireVote: Decodable {
        let proposalID: String
        let voter: String
        let options: [WireOption]?

        enum CodingKeys: String, CodingKey {
            case proposalID = "proposal_id"
            case voter
            case options
        }

        struct WireOption: Decodable {
            let option: String
            let weight: String
        }
    }

    /// Maps to the domain vote. Returns `nil` when the proposal id is
    /// unparseable; unrecognized options are dropped from the array.
    func toVote() -> CosmosGovVote? {
        guard let proposalID = UInt64(vote.proposalID) else { return nil }
        let options = (vote.options ?? []).compactMap { wire -> CosmosGovVoteOption? in
            guard let choice = CosmosGovVoteChoice(wire: wire.option) else { return nil }
            return CosmosGovVoteOption(
                option: choice,
                weight: Decimal(string: wire.weight) ?? 0
            )
        }
        return CosmosGovVote(proposalID: proposalID, voter: vote.voter, options: options)
    }
}

// MARK: - Params

/// Gov tally + voting params relevant to the tab: the voting window length
/// (for the countdown) and the pass/quorum/veto thresholds (for a quorum
/// hint). All durations are seconds; thresholds are `cosmos.Dec` fractions.
struct CosmosGovParams: Equatable, Sendable {
    /// Voting-period length in seconds (live QBTC value = 172800 = 2 days).
    let votingPeriodSeconds: TimeInterval?
    let quorum: Decimal?
    let threshold: Decimal?
    let vetoThreshold: Decimal?
}

/// Response envelope for `GET /cosmos/gov/v1/params/{type}`. v1 consolidates
/// every param under `params`; the deprecated `voting_params` /
/// `deposit_params` / `tally_params` siblings are ignored.
struct CosmosGovParamsResponse: Decodable {
    let params: WireParams?

    struct WireParams: Decodable {
        let votingPeriod: String?
        let quorum: String?
        let threshold: String?
        let vetoThreshold: String?

        enum CodingKeys: String, CodingKey {
            case votingPeriod = "voting_period"
            case quorum
            case threshold
            case vetoThreshold = "veto_threshold"
        }
    }

    func toParams() -> CosmosGovParams {
        CosmosGovParams(
            votingPeriodSeconds: params?.votingPeriod.flatMap(Self.parseDurationSeconds),
            quorum: params?.quorum.flatMap { Decimal(string: $0) },
            threshold: params?.threshold.flatMap { Decimal(string: $0) },
            vetoThreshold: params?.vetoThreshold.flatMap { Decimal(string: $0) }
        )
    }

    /// Parses a Cosmos duration string (`"172800s"`) into seconds. Returns
    /// `nil` for any value that doesn't end in `s` or isn't numeric.
    static func parseDurationSeconds(_ raw: String) -> TimeInterval? {
        guard raw.hasSuffix("s") else { return nil }
        let digits = raw.dropLast()
        guard let seconds = TimeInterval(digits) else { return nil }
        return seconds
    }
}
