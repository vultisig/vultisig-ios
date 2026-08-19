//
//  ProjectionCoordinator.swift
//  VultisigApp
//

import Foundation

enum ProjectionCoordinator {
    static let timeout: Duration = .seconds(5)

    /// Returns wording that remains true even when optional chain state is unavailable.
    static func scope(for decoded: DecodedTransaction) -> String? {
        switch decoded.amount {
        case .fraction(let basisPoints, _):
            return String(
                format: "withdrawingShareOfStakedPosition".localized,
                DecodedTransactionPresentation.percentage(fromBasisPoints: basisPoints)
            )
        case .unstated where decoded.operation == .unstake:
            return "scopeYourWholeStake".localized
        case .unstated where decoded.operation == .claimRewards:
            return "scopeRewardsAccruedSoFar".localized
        case .unstated, .units:
            return nil
        }
    }

    static func hero(
        for decoded: DecodedTransaction,
        title: String,
        estimate: HeroCoinAmount? = nil
    ) -> HeroContent? {
        guard let scope = scope(for: decoded) else { return nil }
        return .projected(title: title, estimate: estimate, scope: scope)
    }

    /// Every read failure, including a timeout, degrades to the signed scope.
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
