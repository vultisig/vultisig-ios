//
//  TransactionHeroResolver.swift
//  VultisigApp
//
//  One explicit hero-provider precedence for initiator and co-signer surfaces.
//  Surface entitlements preserve each screen's previous provider chain.
//

import Foundation

/// Where a hero is being asked for. Each corresponds to one screen.
enum TransactionHeroSurface: Hashable, CaseIterable {
    /// The initiator's Verify screen for a function/DeFi transaction.
    case functionCallVerify
    /// The initiator's Send Verify screen, including TRON resource flows.
    case sendVerify
    /// The initiator's Done screen.
    case sendDone
    /// The co-signer's Verify screen.
    case keysignConfirm
    /// The co-signer's Done screen.
    case keysignDone
}

/// What is being described, from whichever side is asking.
enum TransactionHeroSubject {

    case initiating(SendTransaction)

    /// Simulation stays view-model owned and lazy so earlier providers can win
    /// without triggering async-derived presentation work.
    case cosigning(payload: KeysignPayload?, simulated: () -> HeroContent?)

    /// Final signed content for either Done device. Trusted coins stay local;
    /// the simulation closure is empty on initiator flows.
    case completed(
        payload: KeysignPayload,
        trustedCoins: [Coin],
        simulated: () -> HeroContent?
    )
}

struct TransactionHeroResolution {
    let provider: TransactionHeroProvider.ID
    let hero: HeroContent
}

struct TransactionHeroProvider {

    enum ID: Hashable {
        case rippleTrustSet
        case quotedWithdrawal
        case limitOrderCancel
        case limitOrderPlacement
        case simulated
        case decoded
    }

    let id: ID
    let surfaces: Set<TransactionHeroSurface>
    let hero: (TransactionHeroSubject) -> HeroContent?
}

enum TransactionHeroResolver {

    /// First claimant wins. Specific legacy providers precede simulation;
    /// simulation precedes the general decoder because it has stronger quantity
    /// evidence and can be retitled with the decoded verb.
    static let providers: [TransactionHeroProvider] = [
        .rippleTrustSet,
        .quotedWithdrawal,
        .limitOrderCancel,
        .limitOrderPlacement,
        .simulated,
        .decoded
    ]

    /// Returns the first entitled hero. Injectable providers make precedence
    /// behavior testable rather than merely exposing the registered order.
    static func hero(
        on surface: TransactionHeroSurface,
        for subject: TransactionHeroSubject,
        providers: [TransactionHeroProvider] = TransactionHeroResolver.providers
    ) -> HeroContent? {
        resolution(on: surface, for: subject, providers: providers)?.hero
    }

    static func resolution(
        on surface: TransactionHeroSurface,
        for subject: TransactionHeroSubject,
        providers: [TransactionHeroProvider] = TransactionHeroResolver.providers
    ) -> TransactionHeroResolution? {
        for provider in providers where provider.surfaces.contains(surface) {
            if let hero = provider.hero(subject) {
                return TransactionHeroResolution(provider: provider.id, hero: hero)
            }
        }
        return nil
    }
}

// MARK: - The providers

extension TransactionHeroProvider {

    /// Done-only; Verify already has a TrustSet summary.
    static let rippleTrustSet = TransactionHeroProvider(
        id: .rippleTrustSet,
        surfaces: [.sendDone, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating(let tx):
                return RippleTrustSetPresentation.hero(for: tx)
            case .cosigning(let payload, _):
                return RippleTrustSetPresentation.hero(for: payload)
            case .completed(let payload, _, _):
                return RippleTrustSetPresentation.hero(for: payload)
            }
        }
    )

    /// A cancel is otherwise misread as a send on every legacy surface.
    static let limitOrderCancel = TransactionHeroProvider(
        id: .limitOrderCancel,
        surfaces: [.functionCallVerify, .sendDone, .keysignConfirm, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating(let tx):
                return LimitOrderCancelPresentation.hero(for: tx)
            case .cosigning(let payload, _):
                // Co-signers identify cancels from the signed `m=<` memo.
                return LimitOrderCancelPresentation.hero(forSignedMemo: payload?.memo)
            case .completed(let payload, _, _):
                return LimitOrderCancelPresentation.hero(forSignedMemo: payload.memo)?.retitled(
                    DecodedTransactionPresentation.doneTitle(for: .limitOrderCancel)
                )
            }
        }
    )

    /// Co-signer Verify only, matching the previous surface.
    static let limitOrderPlacement = TransactionHeroProvider(
        id: .limitOrderPlacement,
        surfaces: [.keysignConfirm],
        hero: { subject in
            guard case .cosigning(let payload, _) = subject else { return nil }
            return LimitOrderPlacementPresentation.hero(
                memo: payload?.memo,
                display: LimitOrderPlacementPresentation.display(for: payload)
            )
        }
    )

    /// Co-signer only; simulation requires a built payload.
    static let simulated = TransactionHeroProvider(
        id: .simulated,
        surfaces: [.keysignConfirm, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating:
                return nil
            case .cosigning(let payload, let simulated):
                guard let hero = simulated() else { return nil }
                let verb = payload.flatMap(DecodedTransactionPresentation.operationTitle(for:))
                return hero.retitled(verb)
            case .completed(let payload, _, let simulated):
                guard let hero = simulated() else { return nil }
                return hero.retitled(DoneTransactionPresentation.specificTitle(for: payload))
            }
        }
    )

    /// Initiator-only exact payout, ahead of the decoded fraction.
    static let quotedWithdrawal = TransactionHeroProvider(
        id: .quotedWithdrawal,
        surfaces: [.functionCallVerify],
        hero: { subject in
            switch subject {
            case .initiating(let transaction):
                return QuotedWithdrawalPresentation.hero(for: transaction)
            case .cosigning, .completed:
                return nil
            }
        }
    )

    static let decoded = TransactionHeroProvider(
        id: .decoded,
        surfaces: [.functionCallVerify, .sendVerify, .sendDone, .keysignConfirm, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating(let tx):
                let content = InitiatingTransactionContent(tx)
                return DecodedTransactionPresentation.hero(
                    for: SignedTransactionDecoder.decode(content),
                    coin: tx.coin
                )
            case .cosigning(let payload, _):
                guard let payload else { return nil }
                return DecodedTransactionPresentation.hero(
                    for: SignedTransactionDecoder.decode(payload),
                    coin: payload.coin
                )
            case .completed(let payload, let trustedCoins, _):
                return DoneTransactionPresentation.hero(
                    for: payload,
                    trustedCoins: trustedCoins
                )
            }
        }
    )
}
