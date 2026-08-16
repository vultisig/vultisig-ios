//
//  TransactionHeroResolver.swift
//  VultisigApp
//
//  Which presentation gets to describe a transaction on the screens around
//  signing.
//
//  A handful of transactions cannot be described in the generic send vocabulary:
//  a limit-order cancel moves nothing (or dust), an XRPL TrustSet's amount is a
//  trust-line LIMIT, a staked withdrawal's amount is the literal "0" with the
//  instruction in the memo. Each got a `*Presentation` that returns a `HeroContent`
//  for its own kind of transaction and `nil` for everything else — which is the
//  right shape.
//
//  What was wrong is how the screens asked. Every screen optional-chained its own
//  hand-ordered list of concrete presentations, so "who describes this" was spread
//  across four view files with four different orderings and four different sets of
//  participants. Nothing named the grid, nothing tested it, and each new
//  presentation was another `??` in every screen that should know about it. This
//  is the one place that knows.
//

import Foundation

/// The screen asking for a hero, and therefore which presentations get a say.
///
/// ⚠️ **Load-bearing, not decoration.** The four screens consult three different
/// sets of presentations between them — the two Done screens happen to share one —
/// and collapsing all of them into a single list would change what people see
/// rather than preserve it. A staked-TCY withdrawal,
/// for one, reaches `SendDoneScreen` carrying its `withdrawDisplayAmount` intact
/// (the function-call flow's done screen IS the send one), so admitting the TCY
/// provider there would put a hero on a receipt that has none today. Making the
/// grid explicit is the point; erasing it would be a behaviour change wearing a
/// refactor's clothes.
enum TransactionHeroSurface: Hashable, CaseIterable {
    /// The initiator's Verify for a function call — `FunctionCallVerifyScreen`.
    case functionCallVerify
    /// The initiator's Done for a send or a function call — `SendDoneScreen`.
    case sendDone
    /// A co-signer's Verify — `KeysignMessageConfirmView`.
    case keysignConfirm
    /// A co-signer's Done — `JoinKeysignDoneView`.
    case keysignDone
}

/// What the asking screen actually holds.
///
/// The two shapes are not a convenience. An initiator owns the whole
/// `SendTransaction` it is about to turn into a payload — including fields the
/// builder computed and nothing on the wire carries. A co-signing device receives
/// only the `KeysignPayload` it is asked to sign, so everything it says has to be
/// recoverable from that, which in practice means the memo — the same thing the
/// chain reads. A provider that can only speak one of the two answers `nil` for
/// the other, and that `nil` is an honest statement about what a co-signer can
/// know, not an omission.
enum TransactionHeroSubject {
    /// The initiator's own transaction, before a payload exists.
    case initiating(SendTransaction)
    /// The payload a co-signing device was asked to sign.
    case cosigning(KeysignPayload)
}

/// One presentation's standing claim on the hero slot.
struct TransactionHeroProvider {

    /// Which presentation this entry stands for.
    ///
    /// Exists so the precedence and surface tests can pin the REGISTRY itself
    /// rather than having to build a firing fixture for every provider. The order
    /// and the grid are declared facts; a test that could only observe them
    /// through fixtures would quietly stop pinning them the day a provider's
    /// guard changed.
    enum ID: String, CaseIterable {
        case rippleTrustSet
        case quotedWithdrawal
        case limitOrderCancel
        case limitOrderPlacement
        case decoded
    }

    let id: ID
    /// The screens this provider is entitled to speak on.
    let surfaces: Set<TransactionHeroSurface>
    /// This provider's hero for the subject, or `nil` when the transaction is not
    /// its to describe.
    let hero: (TransactionHeroSubject) -> HeroContent?
}

/// The one thing a screen asks: what is this transaction, and how should it be
/// announced?
enum TransactionHeroResolver {

    /// **Declared precedence.** Providers are asked in this order, and the first
    /// non-`nil` answer wins.
    ///
    /// The order runs from the most authoritative discriminator to the least:
    ///
    /// 1. `rippleTrustSet` — the wire-level `VSTransactionType`, which is on the
    ///    signed payload precisely because an XRPL issued-currency coin is
    ///    otherwise ambiguous about whether it opens a trust line or pays one.
    /// 2. `quotedWithdrawal` — a figure the builder put on the transaction. Exact,
    ///    but it exists only on the initiator's side.
    /// 3. `limitOrderCancel` — the `m=<` memo prefix, which is what THORChain
    ///    itself keys on.
    /// 4. `limitOrderPlacement` — the `=<` prefix, the same family one level less
    ///    specific. Listed after the cancel because a cancel is the narrower
    ///    reading of the two (`m=<` does not start with `=<`, so this is a
    ///    statement of intent rather than a live tie).
    /// 5. `decoded` — whatever `SignedTransactionDecoder` can read off the content
    ///    that will actually be signed. Last on purpose: it is the general
    ///    reading, and every entry above it knows something this one cannot. A
    ///    quoted withdrawal has the position the memo's fraction refers to; the
    ///    decoder can only ever say "50.06% of your staked TCY", which is true but
    ///    worse than the figure the form already resolved.
    ///
    /// ⚠️ **This is real precedence, not a formality.** Nothing in the types
    /// stops two guards firing at once: `SendTransaction` will happily carry a
    /// `withdrawDisplayAmount` AND a `limitCancelContext`, and a TrustSet payload
    /// can carry any memo at all, `m=<` included. That no builder currently emits
    /// such a transaction is a property of the builders, not an invariant — so the
    /// order has to be the answer, and the answer has to be the one the four `??`
    /// chains gave before this existed. `testTheOrderDecidesWhenTwoProvidersBothClaim`
    /// pins the winner for each overlap the type system permits.
    ///
    /// One overlap is no longer hypothetical: a staked withdrawal is claimed by
    /// `quotedWithdrawal` and `decoded` alike, since the builder quoted a payout
    /// for the same memo the decoder reads. The order is what prefers the exact
    /// figure over the fraction, and
    /// `testTheOnlyOverlapBetweenProvidersIsTheDeliberateOne` pins that it stays
    /// the only pair that overlaps.
    static let providers: [TransactionHeroProvider] = [
        .rippleTrustSet,
        .quotedWithdrawal,
        .limitOrderCancel,
        .limitOrderPlacement,
        .decoded
    ]

    /// The hero for `subject` on `surface`, or `nil` when no provider entitled to
    /// speak there recognises it — in which case the screen keeps whatever it
    /// showed before, generic header included.
    static func hero(on surface: TransactionHeroSurface, for subject: TransactionHeroSubject) -> HeroContent? {
        for provider in providers where provider.surfaces.contains(surface) {
            if let hero = provider.hero(subject) {
                return hero
            }
        }
        return nil
    }

    /// An initiator's screen, which holds the whole transaction.
    static func hero(on surface: TransactionHeroSurface, for transaction: SendTransaction) -> HeroContent? {
        hero(on: surface, for: .initiating(transaction))
    }

    /// A co-signer's screen, which holds only the payload it was asked to sign.
    ///
    /// A `nil` payload — these screens render before one has arrived — resolves to
    /// `nil`, exactly like an unrecognised one, so the caller's fallback runs.
    static func hero(on surface: TransactionHeroSurface, for payload: KeysignPayload?) -> HeroContent? {
        guard let payload else { return nil }
        return hero(on: surface, for: .cosigning(payload))
    }
}

private extension TransactionHeroProvider {

    /// An XRPL TrustSet, whose `toAmount` is the trust-line LIMIT rather than a
    /// transfer — without a hero the screens announce a quadrillion-token payment
    /// that never happened, and price it in fiat.
    ///
    /// Absent from `.functionCallVerify` because a TrustSet is not a function call
    /// and never reaches that screen, and from `.keysignConfirm` because a
    /// co-signer's Verify already renders the TrustSet's real terms as its own row
    /// set; giving it a hero there as well is a product change, not this refactor.
    static let rippleTrustSet = TransactionHeroProvider(
        id: .rippleTrustSet,
        surfaces: [.sendDone, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating(let transaction):
                return RippleTrustSetPresentation.hero(for: transaction)
            case .cosigning(let payload):
                return RippleTrustSetPresentation.hero(for: payload)
            }
        }
    )

    /// A withdrawal whose transaction amount is the literal `"0"`, because the
    /// instruction is carried somewhere the amount field is not — the `tcy-:<bps>`
    /// memo, or the receipt shares attached to a `liquid.unbond`.
    ///
    /// ⚠️ **Keyed on the figure, not on the asset.** The guard is "the builder
    /// quoted a payout", so every arm that computes one is described here: staked
    /// TCY and CACAO by their memo's fraction, the RUJI auto-compound redemption by
    /// its share ratio. Narrowing it per asset would mean several providers running
    /// identical code, and an arm that quietly gets no hero the day it gains a
    /// figure.
    static let quotedWithdrawal = TransactionHeroProvider(
        id: .quotedWithdrawal,
        surfaces: [.functionCallVerify],
        hero: { subject in
            switch subject {
            case .initiating(let transaction):
                return QuotedWithdrawalPresentation.hero(for: transaction)
            case .cosigning:
                // ⚠️ A co-signer's screens are the known follow-up, and they are
                // deliberately still `nil` here.
                //
                // The figure the initiator quotes is the memo's fraction applied
                // to the staked position its form was showing; a payload carries
                // the fraction and nothing else. Naming an amount on a co-signer's
                // screen therefore means reading the position off-chain first —
                // real work with a real-funds surface, not a registration. Adding
                // `.keysignConfirm` / `.keysignDone` above is what turns it on
                // once that figure can be trusted.
                return nil
            }
        }
    )

    /// A limit-order cancel, which moves nothing on the THORChain route and only
    /// donated dust on the L1 one — the sole provider every surface asks.
    static let limitOrderCancel = TransactionHeroProvider(
        id: .limitOrderCancel,
        surfaces: [.functionCallVerify, .sendDone, .keysignConfirm, .keysignDone],
        hero: { subject in
            switch subject {
            case .initiating(let transaction):
                return LimitOrderCancelPresentation.hero(for: transaction)
            case .cosigning(let payload):
                return LimitOrderCancelPresentation.hero(forSignedMemo: payload.memo)
            }
        }
    )

    /// A limit-order PLACEMENT seen by a co-signer, reconstructed from its `=<`
    /// memo.
    ///
    /// Co-signer only: the initiator's placement is verified on `SwapVerifyScreen`,
    /// which builds its hero from the live `SwapTransaction.limitContext` and never
    /// produces a `SendTransaction` for this path at all.
    ///
    /// ⚠️ The memo is reconstructed here rather than handed in already parsed, even
    /// though `KeysignMessageConfirmView` computes the same `Display` for its
    /// target-price and expiry rows. Threading a value only one provider wants
    /// through a shared entry point is exactly the coupling this registry removes,
    /// and the cost is splitting a short string twice per render.
    static let limitOrderPlacement = TransactionHeroProvider(
        id: .limitOrderPlacement,
        surfaces: [.keysignConfirm],
        hero: { subject in
            switch subject {
            case .initiating:
                return nil
            case .cosigning(let payload):
                return LimitOrderPlacementPresentation.hero(
                    memo: payload.memo,
                    display: LimitOrderPlacementPresentation.display(for: payload)
                )
            }
        }
    )

    /// Whatever the transaction says about itself, read the way a co-signer reads
    /// its payload.
    ///
    /// A staked deposit carries no `withdrawDisplayAmount` — there is no payout to
    /// quote — so nothing above this claims it, and the screen fell back to
    /// "You're sending" over an operation that is not a transfer. The memo already
    /// says what it is (`tcy+` is a stake, `BOND:` a bond), and
    /// `SignedTransactionDecoder` already reads exactly that for the device on the
    /// other end. This asks it the same question on this side.
    ///
    /// ⚠️ **Derived, not declared.** The alternative was a `functionKind` on every
    /// builder, which was built and then dropped: a declaration is not part of the
    /// signed bytes, so it can contradict them at no cost, and eighteen of them is
    /// eighteen chances to say something the transaction does not. This reads the
    /// same content the chain will, so the two cannot disagree.
    ///
    /// Initiator-only. A co-signer's screens consult the decoder directly through
    /// `JoinKeysignViewModel`, where the reading is composed with a Blockaid
    /// simulation rather than replacing it.
    static let decoded = TransactionHeroProvider(
        id: .decoded,
        surfaces: [.functionCallVerify],
        hero: { subject in
            switch subject {
            case .initiating(let transaction):
                return DecodedTransactionPresentation.hero(
                    for: SignedTransactionDecoder.decode(
                        InitiatingTransactionContent(transaction)
                    ),
                    coin: transaction.coin
                )
            case .cosigning:
                return nil
            }
        }
    )
}
