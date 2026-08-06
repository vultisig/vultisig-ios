//
//  KeyshareNormalizer.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Log.app.store

/// Why a share could not be put into the form the current protection state
/// requires. Each caller maps this onto its own error surface — the two commit
/// paths report failures to very different screens.
enum KeyshareNormalizationFailure: Error {
    /// A sealed share does not open under the current session. `open` reports a
    /// key that is gone, a key that does not fit, and a key merely not yet
    /// unwrapped identically, so this names the share and nothing else.
    case unreadable(pubkey: String)
    /// A readable share cannot be sealed under the current session, or the seal
    /// it produced does not open back to it. Carries the protector's own error,
    /// for a caller that would rather surface that.
    case unsealable(pubkey: String, underlying: Error)
}

/// Puts a vault's key shares on the side of the invariant the passcode is
/// currently on, at the moment they are written — or refuses the write.
///
/// A share is sealed if and only if a passcode is currently set. Two paths hold
/// shares in memory across an interval a passcode transition can run inside: a
/// backup import, across its password prompt and vault picker, and a keygen,
/// across the whole "Review Your Vaults" screen. Neither set of shares is in the
/// store, so the sweep that rewrites every *stored* share cannot reach them —
/// the protection state they were computed under is not necessarily the one they
/// are saved in, and both directions of that mismatch break something:
///
/// - **Sealed, passcode since removed.** The data key is gone, so the persisted
///   vault looks complete, nothing ever revisits it, and every signature it is
///   asked for fails.
/// - **Plaintext, passcode since set.** Key material lands in a protected store
///   in the clear, readable while the app is locked, and stays that way
///   indefinitely, because the sweep that would have sealed it already ran.
///
/// Verifying only closes the first: plaintext is readable, so a readability
/// check waves it through. So the shares are *normalized* rather than checked —
/// opened, then re-sealed under the state in force right now — and the write is
/// refused when that cannot be done. Both callers normalize under a write lease,
/// so "right now" cannot move underneath the save that follows.
///
/// The asymmetry is deliberate. A plaintext share is normalized rather than
/// refused: throwing away a finished keygen — which cannot be repeated without
/// every co-signer back on the same screen — to prevent an exposure that this
/// very write is about to end would cost far more than it saves. A share that
/// does not open has no such repair, and is refused.
///
/// > Note: re-sealing an already-correctly-sealed share produces different bytes
/// > — AES-GCM takes a fresh nonce per seal — so the persisted value is not
/// > byte-identical to the one in memory. It opens to the same share under the
/// > same key, which is the property that matters, and paying a nonce to keep
/// > one code path is cheaper than a "leave it alone if it already verifies"
/// > branch that would have to be right about what "already" means.
///
/// The isolation is on the methods rather than the type: all of the work is
/// main-actor work because `Vault` is a main-actor-only `@Model`, but the value
/// itself is one immutable reference, and the types that own one hold it as a
/// stored property.
struct KeyshareNormalizer {

    private let protector: KeyshareProtecting

    init(protector: KeyshareProtecting) {
        self.protector = protector
    }

    /// Opens every sealed share and changes nothing.
    ///
    /// The first half of ``normalizedShares(of:)``, for a caller that wants to
    /// reject an input it cannot open before it has done anything else with it.
    /// It says nothing about whether the shares can be *stored*; only the
    /// normalization does.
    @MainActor
    func verify(_ vault: Vault) throws {
        for share in vault.keyshares where protector.isSealed(share.keyshare) {
            _ = try opened(share.keyshare, pubkey: share.pubkey)
        }
    }

    /// Every share of the vault, sealed if a passcode is set and plaintext if
    /// not, ready to be assigned back as a whole array.
    ///
    /// A value that opens to *another* sealed value is refused rather than
    /// unwrapped again, matching ``KeyshareSweeper``: an envelope around an
    /// envelope is not a share, and accepting one because its outer layer
    /// authenticated would write `vlt2:` to disk under the name of a key share.
    @MainActor
    func normalizedShares(of vault: Vault) throws -> [KeyShare] {
        try vault.keyshares.map { share in
            let plaintext = protector.isSealed(share.keyshare)
                ? try opened(share.keyshare, pubkey: share.pubkey)
                : share.keyshare

            // A passthrough with no passcode set, which is what keeps an
            // unprotected install byte-identical to one without this feature.
            return KeyShare(
                pubkey: share.pubkey,
                keyshare: try sealed(plaintext, pubkey: share.pubkey),
                keyId: share.keyId
            )
        }
    }

    // MARK: - Privates

    private func opened(_ stored: String, pubkey: String) throws -> String {
        let opened: String
        do {
            opened = try protector.open(stored)
        } catch {
            logger.error(
                "Key share \(pubkey, privacy: .public) could not be opened: \(String(describing: error), privacy: .public)"
            )
            throw KeyshareNormalizationFailure.unreadable(pubkey: pubkey)
        }

        guard !protector.isSealed(opened) else {
            logger.error(
                "Key share \(pubkey, privacy: .public) opened to another sealed value; refusing to treat it as a share"
            )
            throw KeyshareNormalizationFailure.unreadable(pubkey: pubkey)
        }
        return opened
    }

    /// The share as it should be stored, proved to open back to what went in.
    ///
    /// ``KeyshareSweeper`` makes two checks after every seal and only one of
    /// them transfers. Its `isSealed` check catches "no data key is in hand",
    /// which is a failure *there* because the sweep is on its way to sealed;
    /// here a plaintext result is the correct answer whenever no passcode is
    /// set, and asserting otherwise would break every unprotected install.
    ///
    /// The round trip does transfer, and for a sharper reason than the sweep
    /// has: this is the last moment a freshly generated share's plaintext
    /// exists anywhere. Storing ciphertext that does not open back would be
    /// precisely the dead vault the caller is here to prevent, and it would be
    /// stored looking perfectly healthy. A no-passcode install pays nothing for
    /// it — both halves are passthroughs.
    ///
    /// > Note: the write lease keeps a passcode *transition* out of this, but
    /// > `PasscodeService.lock()` is `nonisolated` and takes no lease, so the
    /// > key can be forgotten between the seal and the proof. That is why the
    /// > proof separates "could not open" from "opened to the wrong thing": the
    /// > first is a lock landing mid-normalization, and the caller is told that
    /// > rather than a cipher fault it can do nothing about. Either way the
    /// > write is refused, which is the correct direction to fail — the share is
    /// > intact and the next unlock stores it.
    private func sealed(_ plaintext: String, pubkey: String) throws -> String {
        let sealed: String
        do {
            sealed = try protector.seal(plaintext)
        } catch {
            logger.error(
                "Key share \(pubkey, privacy: .public) could not be sealed: \(String(describing: error), privacy: .public)"
            )
            throw KeyshareNormalizationFailure.unsealable(pubkey: pubkey, underlying: error)
        }

        let reopened: String
        do {
            reopened = try protector.open(sealed)
        } catch {
            logger.error(
                "Key share \(pubkey, privacy: .public) could not be read back after sealing: \(String(describing: error), privacy: .public)"
            )
            throw KeyshareNormalizationFailure.unsealable(pubkey: pubkey, underlying: error)
        }

        guard reopened == plaintext else {
            logger.error("Key share \(pubkey, privacy: .public) did not open back to its original value")
            throw KeyshareNormalizationFailure.unsealable(
                pubkey: pubkey,
                underlying: KeyshareProtectionError.cipherFailure
            )
        }
        return sealed
    }
}
