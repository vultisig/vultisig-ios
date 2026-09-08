//
//  SwapKitResponseAgreement.swift
//  VultisigApp
//

import Foundation

extension SwapKitSwapResponse {

    /// Refuse a response that disagrees with itself about where the deposit goes.
    ///
    /// `targetAddress`, `inboundAddress` and `tx[]` state the same fact independently and the
    /// payload builder reads only the first. Neither is authoritative enough to arbitrate from,
    /// so a divergence is refused rather than resolved by precedence.
    func validateSelfAgreement(fromChain: Chain) throws {
        try validateTransferCardinality()
        try validateDestinationAgreement(fromChain: fromChain)
        try validateDestinationTagAgreement()
    }

    /// Only `tx[0]` is ever built, so a multi-entry array would be signed as a partial deposit,
    /// and an empty one states no transfer while `targetAddress` says otherwise.
    private func validateTransferCardinality() throws {
        guard case .ton(let transfers) = tx else { return }
        guard transfers.count == 1 else {
            throw SwapKitError.contradictoryResponse(
                detail: "TON route returned \(transfers.count) transfers, expected exactly one"
            )
        }
    }

    private func validateDestinationAgreement(fromChain: Chain) throws {
        let target = Self.bareDestination(resolvedTargetAddress)
        guard !target.isEmpty else {
            throw SwapKitError.contradictoryResponse(detail: "targetAddress is empty")
        }
        for candidate in corroboratingDestinations {
            // A present-but-blank field corroborates nothing, and nothing is not agreement:
            // skipping it would let a response walk past this guard with an empty string.
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

    /// Tags are checked separately because the address comparison strips the suffix, which would
    /// otherwise hide one address carrying two different tags — two different recipients. The
    /// switch is exhaustive so a tag source added later has to answer for `.unreadable`.
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

    /// Both sides get the same strip, so one destination spelled with a tag suffix in one field
    /// and without it in another still agrees.
    private static func bareDestination(_ address: String) -> String {
        extractTagSuffix(from: address).address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// TON compares as parsed accounts because one account really does arrive spelled several
    /// ways. Everything else is byte-for-byte on purpose: base58 is case-sensitive. Bech32 and
    /// CashAddr could be case-normalised safely, but do not add it — a false reject here is a
    /// route the user retries, while a wrong canonicalisation lets two addresses pass as one.
    private static func isSameDestination(_ lhs: String, _ rhs: String, chain: Chain) -> Bool {
        chain == .ton ? TonAccountIdentity.isSameAccount(lhs, rhs) : lhs == rhs
    }
}
