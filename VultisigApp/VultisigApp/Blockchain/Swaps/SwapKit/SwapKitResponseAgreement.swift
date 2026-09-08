//
//  SwapKitResponseAgreement.swift
//  VultisigApp
//
//  Fail-closed cross-check of a `/v3/swap` response against itself, run before the
//  quote can enter ranking.
//

import Foundation

extension SwapKitSwapResponse {

    /// Refuse a response that disagrees with itself about where the deposit goes.
    ///
    /// SwapKit states the deposit destination in three independent fields — `targetAddress`,
    /// `inboundAddress`, and the `tx[]` transfer array — and the payload builder reads only
    /// `targetAddress`. A response whose halves diverge would be signed to that field while
    /// the others name a different account, and nothing downstream could tell: Blockaid does
    /// not scan non-EVM SwapKit sources, and the cosigning peer never decodes `tx[]`. Neither
    /// field is authoritative enough to arbitrate from, so a divergence is refused rather
    /// than resolved by precedence.
    ///
    /// The realistic trigger is not a tampered payload but an unversioned wire change —
    /// upstream has already renamed `SOLANA` → `SERIALIZED_BASE64` and `CARDANO` → `CBOR`
    /// mid-flight. Repurposing a destination field the same way would be a lost deposit.
    func validateSelfAgreement(fromChain: Chain) throws {
        try validateTransferCardinality()
        try validateDestinationAgreement(fromChain: fromChain)
        try validateDestinationTagAgreement()
    }

    /// A TON route must state exactly one transfer. Only `tx[0]` is ever built, so a
    /// multi-entry array would be signed as a partial deposit that under-funds the swap,
    /// and an empty array states no transfer at all while `targetAddress` says otherwise.
    private func validateTransferCardinality() throws {
        guard case .ton(let transfers) = tx else { return }
        guard transfers.count == 1 else {
            throw SwapKitError.contradictoryResponse(
                detail: "TON route returned \(transfers.count) transfers, expected exactly one"
            )
        }
    }

    private func validateDestinationAgreement(fromChain: Chain) throws {
        // `targetAddress` is what every SwapKit branch of the payload builder signs to, so a
        // blank value stages an unspendable deposit rather than a contradictory one.
        let target = Self.bareDestination(resolvedTargetAddress)
        guard !target.isEmpty else {
            throw SwapKitError.contradictoryResponse(detail: "targetAddress is empty")
        }
        for candidate in corroboratingDestinations {
            // A field that is present but blank corroborates nothing, and nothing is not
            // agreement. Skipping it would let a response walk past the guard by stating
            // its second destination as an empty string.
            let value = Self.bareDestination(candidate.value)
            guard !value.isEmpty else {
                throw SwapKitError.contradictoryResponse(detail: "\(candidate.field) is empty")
            }
            guard Self.isSameDestination(value, target, chain: fromChain) else {
                throw SwapKitError.contradictoryResponse(
                    detail: "targetAddress is \(target) but \(candidate.field) is \(value)"
                )
            }
        }
    }

    /// On XRP the destination tag is half the destination: a shared exchange address routes
    /// the deposit to an account by tag, so the same address carrying two different tags is
    /// two different recipients. The address comparison strips the tag suffix on purpose (so
    /// one destination spelled with and without it still agrees), which would hide exactly
    /// that divergence — hence tags are cross-checked in their own right, across every source
    /// the response states one in.
    ///
    /// A source is switched over exhaustively rather than reduced to `UInt64?` first: a tag
    /// the response states but this client cannot read is not a tag-less payment, and
    /// collapsing the two would send a deposit with no tag to an address where the tag is
    /// what identifies the depositor. Any tag source added here later has to answer for
    /// `.unreadable` before it will compile.
    private func validateDestinationTagAgreement() throws {
        var stated: [(field: String, value: UInt64)] = []
        for source in destinationTagSources {
            switch source.tag {
            case .absent:
                continue
            case .unreadable(let reason):
                throw SwapKitError.contradictoryResponse(
                    detail: "\(source.field) states a destination tag that cannot be read: \(reason)"
                )
            case .tag(let value):
                stated.append((field: source.field, value: value))
            }
        }
        guard let primary = stated.first else { return }
        for candidate in stated.dropFirst() where candidate.value != primary.value {
            throw SwapKitError.contradictoryResponse(
                detail: "\(primary.field) is \(primary.value) but \(candidate.field) is \(candidate.value)"
            )
        }
    }

    /// Every source the response can state a destination tag in, in the order
    /// `resolvedDestinationTag` resolves them, plus the `inboundAddress` suffix — a tag
    /// stated there is still the response contradicting itself even though nothing reads it.
    private var destinationTagSources: [(field: String, tag: SwapKitDestinationTag)] {
        [
            (field: "destinationTag", tag: destinationTagSource),
            (field: "meta.destinationTag", tag: meta.destinationTagSource),
            (field: "targetAddress tag suffix", tag: Self.extractTagSuffix(from: targetAddress).tag),
            (
                field: "inboundAddress tag suffix",
                tag: inboundAddress.map { Self.extractTagSuffix(from: $0).tag } ?? .absent
            )
        ]
    }

    /// Every field other than `targetAddress` that states the same deposit destination.
    /// `inboundAddress` is one on every non-EVM route (EVM omits it); `tx[0].address` is one
    /// wherever the wire shape is a typed transfer array.
    private var corroboratingDestinations: [(field: String, value: String)] {
        var candidates: [(field: String, value: String)] = []
        if let inboundAddress {
            candidates.append((field: "inboundAddress", value: inboundAddress))
        }
        if case .ton(let transfers) = tx, let first = transfers.first {
            candidates.append((field: "tx[0].address", value: first.address))
        }
        return candidates
    }

    /// Both sides of a comparison get the same destination-tag strip, so a destination
    /// spelled with a suffix in one field and without it in another still agrees. The tags
    /// themselves are compared separately — see `validateDestinationTagAgreement`.
    private static func bareDestination(_ address: String) -> String {
        extractTagSuffix(from: address).address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// TON spells one account as `EQ…`, `UQ…` or raw `workchain:hash`, and SwapKit really does
    /// return different spellings for one account, so its destinations compare as parsed
    /// accounts.
    ///
    /// Every other chain compares byte for byte. Base58 is case-sensitive, so folding case
    /// there would let two different addresses pass as one — the one failure this guard must
    /// never have. Bech32 and CashAddr *are* case-insensitive and could be normalised safely,
    /// but no recorded response has ever spelled a destination two ways outside TON, so the
    /// extra parsing would be untested surface in the code that has to be trusted most. The
    /// cost of that choice is bounded: an encoding that starts varying its case gets a
    /// refused route the user can retry, never a deposit signed to the wrong address.
    private static func isSameDestination(_ lhs: String, _ rhs: String, chain: Chain) -> Bool {
        chain == .ton ? TonAccountIdentity.isSameAccount(lhs, rhs) : lhs == rhs
    }
}
