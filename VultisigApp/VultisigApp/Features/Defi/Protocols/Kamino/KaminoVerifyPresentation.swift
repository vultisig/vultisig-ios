//
//  KaminoVerifyPresentation.swift
//  VultisigApp
//

import BigInt
import Foundation

/// What the verify and join screens show for a Kamino Earn transaction, and
/// whether the bytes agree with the claim being made about them.
///
/// Two devices reach this from opposite directions. The initiator built the
/// transaction and holds `KaminoKeysignPayload` — the exact vault, operation and
/// amount it asked for. A co-signer holds only what crossed the wire: the raw
/// bytes, plus `toAddress` and `toAmount`. Both run the same decode, and both
/// then check it against whatever claim their own device is displaying. The
/// check is the point: a decode that matched nothing would just be a second
/// opinion nobody could act on, and a claim with no decode behind it is what a
/// co-signer has today.
///
/// A disagreement is a refusal, not a cosmetic note. The bytes are the only
/// thing that gets signed, so if the summary above them says something else,
/// one of the two is wrong and the user cannot tell which.
enum KaminoVerifyPresentation {

    /// Why a decode and a claim did not agree. Each case names the field, so the
    /// screen can say what disagreed rather than only that something did.
    enum Disagreement: String, Equatable {
        case vault
        case operation
        case amount
        case destination
        /// The account paying for and authorising the transaction is not the one
        /// the summary's "from" row names.
        case signer
        /// The coin the summary scales and labels its amount with is not the
        /// vault's underlying asset, so the figure above is rendered at the
        /// wrong precision or under the wrong ticker.
        case asset
        /// The ComputeBudget the bytes carry is not the one the payload records,
        /// so the fee row describes a different transaction — and a payload whose
        /// budget was stripped is a shape the initiating device's own validator
        /// refuses.
        case priorityFee
    }

    enum State: Equatable {
        /// Not a Kamino transaction. Every other flow renders unchanged.
        case notKamino
        /// The bytes invoke the kVaults program but do not decode to a deposit
        /// or withdraw this app recognises. Surfaced loudly: an unreadable
        /// Kamino transaction is the one case where "nothing to show" would be
        /// the most misleading thing to show.
        case unreadable
        /// The decode and the claim agree.
        case verified(Display)
        /// Everything comparable agrees, but the prominent amount above is not
        /// one this device can check against the bytes. Exactly one situation
        /// reaches it: a WITHDRAW on a co-signer, whose summary shows a token
        /// projection of a share figure at a rate that never crossed the wire.
        /// Calling that `verified` would put the word on a number nothing
        /// verified; refusing it would break every legitimate peer withdraw. So
        /// it is its own answer, and the screen says which number IS from the
        /// bytes.
        case amountUnverifiable(Display)
        /// They do not. The decode is still shown — it describes the bytes,
        /// which is what will be signed — alongside what disagreed.
        case mismatch(Display, Disagreement)

        var display: Display? {
            switch self {
            case .verified(let display), .amountUnverifiable(let display), .mismatch(let display, _):
                return display
            case .notKamino, .unreadable:
                return nil
            }
        }

        /// Whether anything is left to render below the summary's own rows.
        ///
        /// Since the vault, curator and action moved into those rows, a verified
        /// deposit with no rent disclosure has nothing further to say — and
        /// rendering it anyway costs a separator and a blank band under the fee.
        /// A withdraw still carries its share figure, and every state that warns
        /// about something always renders.
        var hasVisibleDetail: Bool {
            switch self {
            case .notKamino:
                return false
            case .unreadable, .amountUnverifiable, .mismatch:
                return true
            case .verified(let display):
                return display.amountAddsInformation || display.strandsWrappedSolRent
            }
        }

        var isMismatch: Bool {
            if case .mismatch = self { return true }
            return false
        }

        /// Whether this transaction must not be signed.
        ///
        /// A decode that contradicts the summary, and a Kamino transaction that
        /// cannot be decoded at all, are both refusals: the bytes are the only
        /// thing that gets signed, so a screen that disagrees with them — or
        /// cannot read them — has nothing to offer an approver. `.notKamino`
        /// and `.amountUnverifiable` are not refusals in themselves; the second
        /// is a disclosed limit on what could be checked, not a contradiction.
        ///
        /// The `u64::MAX` withdraw-everything sentinel is, though, and on any
        /// device. This app cannot produce one: the form's maximum is derived to
        /// sit strictly below the balance precisely so the API never answers
        /// with the sentinel, and the validator pins the instruction's amount to
        /// the request. So a transaction carrying it did not come from here —
        /// and it is the one amount whose consequence is the whole position
        /// rather than the number on screen. Disclosing it while allowing the
        /// signature would put the entire position behind a label.
        var blocksSigning: Bool {
            switch self {
            case .mismatch, .unreadable:
                return true
            case .verified(let display), .amountUnverifiable(let display):
                return display.withdrawsEntirePosition
            case .notKamino:
                return false
            }
        }
    }

    /// The human-readable claim, derived entirely from the bytes and the
    /// registry.
    struct Display: Equatable {
        let operation: KaminoKeysignPayload.Operation
        let vaultName: String
        let vaultAddress: String
        let curator: String
        let riskTier: KaminoRiskTier
        /// The amount in plain human units, at the operation's own scale.
        let amount: String
        /// The unit that amount is in — the vault's asset ticker for a deposit,
        /// a share label for a withdraw. A withdraw's bytes are denominated in
        /// SHARES while the summary above shows the asset projection, so naming
        /// the unit is what keeps the two from reading as a contradiction.
        let unit: String
        let strandsWrappedSolRent: Bool
        /// The withdraw carries `u64::MAX`, which the program reads as "withdraw
        /// everything" rather than as a share count.
        let withdrawsEntirePosition: Bool

        /// The amount as the screen should read it. The sentinel is not a
        /// quantity, so it is not rendered as one.
        var amountWithUnit: String {
            withdrawsEntirePosition ? "kaminoVerifyEntirePosition".localized : "\(amount) \(unit)"
        }

        /// Whether the decoded amount says something the summary's own headline
        /// does not.
        ///
        /// A deposit's bytes carry the same token amount the header already
        /// shows, so repeating it is noise. A withdraw's carry SHARES against a
        /// header showing a token projection, and a full exit carries a sentinel
        /// rather than a quantity — in both cases this is the only figure on
        /// screen that came from what will be signed.
        var amountAddsInformation: Bool {
            operation == .withdraw || withdrawsEntirePosition
        }

        /// Names the operation where the summary would otherwise say "you're
        /// sending", which describes a transfer — the one thing a vault deposit
        /// is not. Deliberately carries the protocol name: on a co-signer this
        /// line is the first thing that says what is being approved.
        var headerTitle: String {
            switch operation {
            case .deposit: return "kaminoVerifyHeaderDeposit".localized
            case .withdraw: return "kaminoVerifyHeaderWithdraw".localized
            }
        }

        /// Curator and risk tier as one value, so the pair fits a standard
        /// summary row instead of needing a section that can style a trailing tag.
        var curatorWithRiskTier: String {
            "\(curator) · \(riskTier.title)"
        }
    }

    /// Resolves the state for a payload, on either device.
    static func state(for payload: KeysignPayload?) -> State {
        // Deliberately NOT gated on `payload.coin.chain`. That field is relayed
        // metadata, so gating on it would let whoever supplied it switch this
        // decode off — and the classification does not need it: `signSolana`
        // already means raw Solana bytes, and the kVaults program id is read out
        // of the bytes themselves. A coin that disagrees with them is a mismatch
        // below, not a reason to stay quiet.
        guard let payload, let signSolana = payload.signSolana else { return .notKamino }

        // Parse everything first, then ask whether ANY of it is Kamino's. Doing
        // it the other way round — bailing out early on a batch, or on a
        // transaction that would not parse — is how a Kamino transaction smuggled
        // alongside another one would render as an ordinary Solana payload and
        // say nothing at all. Bytes that parse to nothing Kamino-shaped still
        // fall through to `.notKamino`, which leaves every other flow untouched.
        let parsed = signSolana.rawTransactions.compactMap {
            try? SolanaV0Transaction(base64Transaction: $0)
        }
        // Bytes this app cannot parse are still bytes it would SIGN — the raw
        // Solana path hashes the wire message verbatim and does not care what
        // version it is. So a legacy transaction invoking kVaults must not fall
        // through `compactMap` into silence; if any unparseable entry mentions
        // the program, the whole payload is unreadable.
        let unparseableMentionsKamino = parsed.count != signSolana.rawTransactions.count
            && signSolana.rawTransactions.contains {
                (try? SolanaV0Transaction(base64Transaction: $0)) == nil
                    && KaminoTransactionDecoder.mentionsKaminoVaultProgram(base64Transaction: $0)
            }
        if unparseableMentionsKamino { return .unreadable }

        guard parsed.contains(where: KaminoTransactionDecoder.invokesKaminoVault) else {
            return .notKamino
        }
        guard parsed.count == signSolana.rawTransactions.count,
              parsed.count == 1,
              let decoded = KaminoTransactionDecoder.decode(parsed[0])
        else {
            return .unreadable
        }

        let display = self.display(for: decoded)
        if let disagreement = disagreement(between: decoded, and: payload) {
            return .mismatch(display, disagreement)
        }
        // A co-signer's withdraw: the destination checked out, but the amount the
        // summary leads with did not — and cannot. Say so rather than stamping
        // the whole screen verified on the strength of the one field that could
        // be compared.
        if payload.kaminoPayload == nil, decoded.operation == .withdraw {
            return .amountUnverifiable(display)
        }
        return .verified(display)
    }

    // MARK: - Private

    private static func display(for decoded: KaminoDecodedTransaction) -> Display {
        Display(
            operation: decoded.operation,
            vaultName: decoded.descriptor.fallbackName,
            vaultAddress: decoded.descriptor.address,
            curator: decoded.descriptor.curator,
            riskTier: decoded.descriptor.riskTier,
            amount: decoded.amountString,
            unit: unit(for: decoded),
            strandsWrappedSolRent: decoded.strandsWrappedSolRent,
            withdrawsEntirePosition: decoded.withdrawsEntirePosition
        )
    }

    /// The unit label for the decoded amount.
    ///
    /// A deposit's `u64` is in the vault's underlying token, so it is named with
    /// that token's ticker — resolved from the pinned mint, never from the coin
    /// the payload happens to carry. A withdraw's is in shares, which have no
    /// ticker a user would recognise, so they are named as what they are.
    private static func unit(for decoded: KaminoDecodedTransaction) -> String {
        switch decoded.operation {
        case .deposit:
            return decoded.descriptor.underlyingCoinMeta?.ticker ?? "kaminoVerifyTokens".localized
        case .withdraw:
            return "kaminoVerifyShares".localized
        }
    }

    /// Checks the decode against whatever claim this device is in a position to
    /// make, and returns the first field that disagrees.
    ///
    /// The two devices check different things because they hold different
    /// claims, and neither is asked to check something it cannot know:
    ///
    /// - **The initiator** holds `kaminoPayload`, the record of what it asked
    ///   the API for. Vault, operation and the exact base-unit amount are all
    ///   comparable, so all three are compared. This is the strong check.
    /// - **A co-signer** holds no marker — it is local to the initiating device
    ///   — but `toAddress` and `toAmount` did cross the wire, and they are the
    ///   values the summary above is rendered from. A deposit's destination is
    ///   the vault and its `toAmount` is the same token base-unit figure the
    ///   instruction carries, so both are compared. A withdraw's destination is
    ///   the user's own account, which is comparable; its `toAmount` is a token
    ///   projection of a SHARE amount at a rate that never crossed the wire, so
    ///   it is deliberately NOT compared. Inventing a tolerance there would
    ///   produce a check that passes for the wrong reasons.
    private static func disagreement(
        between decoded: KaminoDecodedTransaction,
        and payload: KeysignPayload
    ) -> Disagreement? {
        // Checked on both devices, before anything else, because it is the row
        // both screens render at the top: the summary's "from" is
        // `payload.coin.address`, and the account that actually pays for and
        // authorises the transaction is the fee payer in the bytes. A signature
        // by the vault's key only settles for a transaction the vault pays for,
        // so a disagreement here cannot make somebody else's transaction the
        // vault's — but it can make the screen name an account that has nothing
        // to do with what is being signed.
        guard payload.coin.chain == KaminoVaultRegistry.chain else { return .asset }
        guard payload.coin.address == decoded.signer else { return .signer }
        if let asset = decoded.descriptor.underlyingCoinMeta {
            // The summary scales and labels `toAmount` with this coin, so a coin
            // that is not the vault's underlying asset renders the headline
            // figure at the wrong precision or under the wrong ticker. Skipped
            // when the token store cannot resolve the mint — an unestablished
            // fact is not a contradiction.
            // Ticker too, not only the mint and scale. The summary's hero reads
            // "You're sending <amount> <coin.ticker>", so a payload carrying the
            // right mint under a false ticker renders a true number beside the
            // wrong asset name.
            guard payload.coin.decimals == asset.decimals,
                  payload.coin.contractAddress == asset.contractAddress,
                  payload.coin.ticker.caseInsensitiveCompare(asset.ticker) == .orderedSame
            else { return .asset }
        }

        // The compute budget is compared on BOTH devices, because the two claims
        // are genuinely independent: `chainSpecific` records what the initiating
        // device injected and drives the fee row, while the bytes record what the
        // network will charge. A relay that stripped both instructions would
        // otherwise leave a screen quoting a priority fee for a transaction that
        // pays none — and the initiating validator refuses precisely that shape,
        // so a co-signer accepting it would be the weaker of the two devices.
        guard priorityFeeAgrees(decoded: decoded, chainSpecific: payload.chainSpecific) else {
            return .priorityFee
        }

        if let marker = payload.kaminoPayload {
            guard marker.vaultAddress == decoded.descriptor.address else { return .vault }
            guard marker.operation == decoded.operation else { return .operation }
            guard marker.amountDecimals == decoded.amountDecimals,
                  marker.amountBaseUnits == String(decoded.amountBaseUnits)
            else { return .amount }
            return nil
        }

        switch decoded.operation {
        case .deposit:
            guard payload.toAddress == decoded.descriptor.address else { return .destination }
            guard payload.toAmount == decoded.amountBaseUnits else { return .amount }
            return nil
        case .withdraw:
            guard payload.toAddress == decoded.signer else { return .destination }
            return nil
        }
    }
}

private extension KaminoVerifyPresentation {

    /// Whether the ComputeBudget in the bytes is the one the payload records.
    ///
    /// "Neither has one" agrees; "one has one and the other does not" does not.
    static func priorityFeeAgrees(
        decoded: KaminoDecodedTransaction,
        chainSpecific: BlockChainSpecific
    ) -> Bool {
        guard case .Solana(_, let price, let limit, _, _, _) = chainSpecific else {
            // Not a Solana payload at all — the asset check already refused it,
            // and there is nothing here to compare against.
            return false
        }

        let recorded: KaminoPriorityFee?
        if price > 0, limit > 0 {
            guard let price = UInt64(exactly: price), let limit = UInt32(exactly: limit) else { return false }
            recorded = KaminoPriorityFee(limit: limit, price: price)
        } else {
            recorded = nil
        }
        return recorded == decoded.priorityFee
    }
}

extension KaminoVerifyPresentation.Disagreement {
    /// Localised explanation of what disagreed, for the refusal banner.
    var explanation: String {
        switch self {
        case .vault: return "kaminoVerifyMismatchVault".localized
        case .operation: return "kaminoVerifyMismatchOperation".localized
        case .amount: return "kaminoVerifyMismatchAmount".localized
        case .destination: return "kaminoVerifyMismatchDestination".localized
        case .signer: return "kaminoVerifyMismatchSigner".localized
        case .asset: return "kaminoVerifyMismatchAsset".localized
        case .priorityFee: return "kaminoVerifyMismatchPriorityFee".localized
        }
    }
}
