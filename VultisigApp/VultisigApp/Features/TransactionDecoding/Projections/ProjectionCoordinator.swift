//
//  ProjectionCoordinator.swift
//  VultisigApp
//
//  Turning a decoded reading into a hero that says what is certain immediately,
//  and what is estimated when it arrives.
//

import Foundation

enum ProjectionCoordinator {

    /// Short enough that optional chain state cannot stall signing UI.
    static let timeout: Duration = .seconds(5)

    /// Returns a committed scope only for quantities settled at execution.
    static func scope(for decoded: DecodedTransaction) -> String? {
        switch decoded.amount {
        case .fraction(let basisPoints, _):
            // The signed share remains exact even when the projected amount is not.
            return String(
                format: "withdrawingShareOfStakedPosition".localized,
                DecodedTransactionPresentation.percentage(fromBasisPoints: basisPoints)
            )
        case .unstated where decoded.operation == .unstake:
            return "scopeYourWholeStake".localized
        case .unstated where decoded.operation == .claimRewards:
            return "scopeRewardsAccruedSoFar".localized
        case .accountFunding where decoded.operation == .delegate:
            return "scopeDelegatedAmountAfterRent".localized
        case .accountFunding, .unstated, .units:
            return nil
        }
    }

    /// Builds the immediate verb-and-scope hero; an estimate is optional.
    static func hero(
        for decoded: DecodedTransaction,
        title: String,
        estimate: HeroCoinAmount? = nil
    ) -> HeroContent? {
        guard let scope = scope(for: decoded) else { return nil }
        return .projected(title: title, estimate: estimate, scope: scope)
    }

    /// Reads an optional estimate; every failure degrades to the existing scope.
    static func estimate(
        for decoded: DecodedTransaction,
        using resolvers: [ProjectionResolving]
    ) async -> HeroCoinAmount? {
        guard let key = ProjectionQueryKey(decoded),
              let resolver = resolvers.first(where: { $0.handles(decoded.operation) })
        else { return nil }

        return await estimate {
            await resolver.projection(for: decoded, key: key)
        }
    }

    /// Applies the same deadline to every optional position read.
    static func estimate(
        using read: @escaping () async -> HeroCoinAmount?
    ) async -> HeroCoinAmount? {
        // A task group would await a cancellation-ignoring loser on scope exit.
        // The continuation returns on the first result without joining the loser.
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)

            Task {
                let value = await read()
                await gate.resume(with: value)
            }

            Task {
                try? await Task.sleep(for: timeout)
                await gate.resume(with: nil)
            }
        }
    }

    /// Serializes the read/timeout race and resumes the continuation once.
    private actor ResumeOnce {
        private var continuation: CheckedContinuation<HeroCoinAmount?, Never>?

        init(_ continuation: CheckedContinuation<HeroCoinAmount?, Never>) {
            self.continuation = continuation
        }

        func resume(with value: HeroCoinAmount?) {
            guard let pending = continuation else { return }
            continuation = nil
            pending.resume(returning: value)
        }
    }
}
