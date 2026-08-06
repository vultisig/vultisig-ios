//
//  BiometricUnlockStore.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import LocalAuthentication
import OSLog
import Security

private let logger = Log.app.store

/// Whether this device can hold a biometry-guarded copy of the data key *right
/// now*, and if not, why.
///
/// The reason is worth carrying rather than collapsing to a `Bool`, because the
/// two failures need opposite things from the user. Nothing enrolled is fixed in
/// Settings in ten seconds; no hardware is not fixable at all, and offering a
/// switch that can only ever refuse is worse than not offering it.
///
/// Deliberately asked *before* the Keychain write rather than inferred from its
/// failure. `SecItemAdd` under `.biometryCurrentSet` answers a handful of
/// statuses for "the access control cannot be satisfied", they are not
/// documented as an exhaustive set, and mapping them backwards into a reason
/// would be guessing at what the user has to do next.
enum BiometricAvailability: Equatable {
    case available
    /// Hardware is present, nothing is enrolled on it. Also the state a
    /// simulator is in until Face ID is enrolled from the Features menu, which
    /// is where this most often bites during development.
    case notEnrolled
    /// No biometric hardware, biometry locked out after too many failures, or a
    /// device with no passcode — none of which the app can do anything about.
    case unavailable
}

enum BiometricUnlockError: Error, Equatable {
    case notEnabled
    case unavailable
    case cancelled
    case failed
    case storageFailed
    /// Nothing is enrolled, so the item could never be guarded. Distinct from
    /// `.storageFailed` because it is the user's to fix and the message can say
    /// how.
    case notEnrolled
    /// The stored copy was made for a different wrapped key, so it holds a data
    /// key nothing on disk wraps any more.
    case supersededCopy
    /// The stored copy is not the right shape to be a bound data key.
    ///
    /// Separate from `.failed` because the biometric match *succeeded*: the user
    /// watched it work and then nothing happened, which is worth telling them
    /// about, whereas a mismatch or a lockout is not.
    case malformedCopy
}

/// Seam over the biometry-protected Keychain item, so the fail-closed behaviour
/// can be tested without a device and without real Face ID.
protocol BiometricKeychainProtecting {
    /// Adds the item. It is an add and not an upsert, so the caller removes any
    /// existing item first — which is what `BiometricUnlockStore.enable` does,
    /// where a test can see it.
    func store(_ data: Data, account: String) throws
    func read(account: String, prompt: String) throws -> Data
    func delete(account: String) throws
    func exists(account: String) -> Bool
}

/// An optional shortcut past the passcode, never a replacement for it.
///
/// Holds a second copy of the data key behind `SecAccessControl(.biometryCurrentSet)`.
/// The passcode-wrapped copy is untouched and always works, so this can be
/// removed, invalidated or fail without the user losing access to anything.
///
/// `.biometryCurrentSet` rather than `.biometryAny`: the copy is destroyed by the
/// system if the enrolled biometrics change, so enrolling a new face or finger
/// does not silently inherit access to the wallet.
///
/// **Everything here fails closed.** Any error — unavailable, cancelled, lockout,
/// changed enrolment, missing item — throws, and the caller falls back to the
/// passcode. A biometric lock that fails *open* is worse than no lock, and we
/// have shipped that bug before in another app.
///
/// **The copy is bound to the wrapper it was made for**, and that is what makes
/// it safe to unlock with. Nothing here can prove a stored key opens anything:
/// the passcode-wrapped copy cannot be unwrapped without the passcode, and an
/// interrupted `setPasscode` can leave a store with no sealed share to test
/// against. So a copy surviving from a previous install would otherwise hand
/// back key A while the durable wrapper holds key B — and the resume sweep that
/// follows every app unlock would then seal every share under A, which no
/// wrapper holds and nothing can ever open. Binding to the wrapped blob's digest
/// makes that mismatch detectable *before* the key is adopted, and the stale copy
/// is removed rather than left to fail again.
final class BiometricUnlockStore {

    static let shared = BiometricUnlockStore()

    private static let account = "com.vultisig.wallet.biometricDataKey"

    /// The stored blob is the binding followed by the data key.
    private static let bindingLength = SHA256.byteCount
    private static var blobLength: Int { bindingLength + VaultCryptoEnvelope.keyLengthBytes }

    private let keychain: BiometricKeychainProtecting
    /// Its own seam rather than a member of ``BiometricKeychainProtecting``.
    /// That protocol has four conformers spread across this stack's branches, and
    /// none of the other three has anything to say about `LAContext` — adding a
    /// requirement would have made every one of them answer a question it does
    /// not own, with `.available` as the only answer available to them. A
    /// fail-closed component should not acquire a default that fails open.
    private let biometryAvailability: () -> BiometricAvailability

    init(
        keychain: BiometricKeychainProtecting = BiometricKeychain(),
        biometryAvailability: @escaping () -> BiometricAvailability = BiometricKeychain.currentAvailability
    ) {
        self.keychain = keychain
        self.biometryAvailability = biometryAvailability
    }

    var isEnabled: Bool {
        keychain.exists(account: Self.account)
    }

    var availability: BiometricAvailability {
        biometryAvailability()
    }

    /// Stores the data key behind biometry, bound to the wrapped key it belongs
    /// to. Requires the caller to already hold the data key, i.e. to be
    /// unlocked — this never mints or unwraps a key itself.
    ///
    /// Writing the item never prompts for biometry; only reading does. That is
    /// what makes rebinding after a passcode change silent.
    func enable(dataKey: SymmetricKey, boundTo wrappedDataKey: Data) throws {
        // Asked first, so the common refusal arrives as something the user can
        // act on. Without it every one of these came back as a bare storage
        // failure, and the screen above said nothing at all — the switch simply
        // returned to off, which reads as the app ignoring the tap.
        switch biometryAvailability() {
        case .available:
            break
        case .notEnrolled:
            throw BiometricUnlockError.notEnrolled
        case .unavailable:
            throw BiometricUnlockError.unavailable
        }

        var blob = Self.binding(for: wrappedDataKey)
        blob.append(dataKey.withUnsafeBytes { Data($0) })

        // Replace, never update in place: an item's access control cannot be
        // changed after the fact, and adding over one that is already there
        // answers `errSecDuplicateItem`. That matters because rebinding after a
        // passcode change goes through here — without the removal, the change
        // would silently leave the shortcut bound to the old wrapper and the
        // next unlock would refuse it.
        //
        // The removal is not verified: `store` below is the operation that has
        // to succeed, and a stale item that somehow survives is refused by its
        // binding rather than trusted.
        try? keychain.delete(account: Self.account)

        do {
            try keychain.store(blob, account: Self.account)
        } catch {
            logger.error("Failed to store the biometric data key: \(String(describing: error), privacy: .public)")
            throw BiometricUnlockError.storageFailed
        }
    }

    /// - Throws: when the copy could not be confirmed gone. A survivor holds the
    ///   same data key, so it would quietly become a working shortcut again the
    ///   next time a passcode is set — an enablement the user never made.
    func disable() throws {
        try keychain.delete(account: Self.account)

        guard !isEnabled else {
            logger.error("Biometric data key still present after deletion")
            throw BiometricUnlockError.storageFailed
        }
    }

    /// - Parameter wrappedDataKey: the wrapper the app is unlocking against. The
    ///   stored copy has to have been made for exactly this blob.
    /// - Returns: the data key, only on a successful biometric match against a
    ///   copy that still belongs to the current wrapper.
    /// - Throws: on every other outcome, so the caller shows the passcode screen.
    func unlock(reason: String, boundTo wrappedDataKey: Data) throws -> SymmetricKey {
        guard isEnabled else { throw BiometricUnlockError.notEnabled }

        let raw: Data
        do {
            raw = try keychain.read(account: Self.account, prompt: reason)
        } catch let error as BiometricUnlockError {
            throw error
        } catch {
            logger.error("Biometric unlock failed: \(String(describing: error), privacy: .public)")
            throw BiometricUnlockError.failed
        }

        guard raw.count == Self.blobLength else {
            // Present but the wrong shape. Remove it rather than leave a
            // shortcut that cannot work; the passcode still opens the app.
            logger.error("Biometric data key has unexpected length \(raw.count, privacy: .public)")
            try? disable()
            throw BiometricUnlockError.malformedCopy
        }

        guard raw.prefix(Self.bindingLength) == Self.binding(for: wrappedDataKey) else {
            // The wrapper this copy was made for is not the one on disk: a
            // previous install's leftover, or one a passcode change could not
            // rebind. The key inside opens nothing the current wrapper protects,
            // and adopting it would let the resume sweep seal every share under
            // a key nothing wraps.
            logger.error("Biometric data key belongs to a superseded wrapped key; removing it")
            try? disable()
            throw BiometricUnlockError.supersededCopy
        }

        return SymmetricKey(data: raw.suffix(VaultCryptoEnvelope.keyLengthBytes))
    }

    /// Not a secret, and not an authenticator: the blob it digests already sits
    /// unprotected in the Keychain. All it establishes is that two wrapped keys
    /// are the same one — the half of the item worth protecting is the key that
    /// follows it.
    private static func binding(for wrappedDataKey: Data) -> Data {
        Data(SHA256.hash(data: wrappedDataKey))
    }
}

/// The real Keychain item, guarded by `SecAccessControl`.
struct BiometricKeychain: BiometricKeychainProtecting {

    func store(_ data: Data, account: String) throws {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            // `WhenPasscodeSetThisDeviceOnly`: a device with no passcode cannot
            // meaningfully protect this, and the item must never leave the device.
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            throw BiometricUnlockError.unavailable
        }

        let query: [String: Any] = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecUseDataProtectionKeychain): kCFBooleanTrue as Any,
            String(kSecAttrAccount): account,
            String(kSecValueData): data,
            String(kSecAttrAccessControl): access
        ]

        // A pure add. Removing whatever was there is the caller's job, and it
        // has to be — `SecItemDelete` takes a *search* query, so handing it this
        // dictionary would ask it to match on the value and access control it is
        // about to add, and a delete that quietly matches nothing turns the add
        // into `errSecDuplicateItem`.
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            // The status is the only thing that says *why*, and it is about to
            // be thrown away by the mapping. Everything upstream sees
            // `.storageFailed`, so without this line a failure here is
            // undiagnosable from a device log.
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            logger.error(
                "SecItemAdd for the biometric data key failed: \(status, privacy: .public) (\(message, privacy: .public))"
            )
            throw BiometricUnlockError.storageFailed
        }
    }

    static func currentAvailability() -> BiometricAvailability {
        var error: NSError?
        let context = LAContext()
        guard !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .available
        }

        // `.biometryNotEnrolled` and `.passcodeNotSet` are both "turn something
        // on in Settings", and they arrive together: enrolling a face requires a
        // device passcode, so a device with neither reports whichever it checks
        // first. Treating them as one state keeps the message honest without
        // pretending to know which of the two the user is missing.
        switch (error as? LAError)?.code {
        case .biometryNotEnrolled, .passcodeNotSet:
            return .notEnrolled
        default:
            return .unavailable
        }
    }

    func read(account: String, prompt: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = prompt
        // Hides the fallback button. Note that this is presentation only — what
        // actually prevents the device passcode from satisfying this read is the
        // access control: `.biometryCurrentSet` demands currently-enrolled
        // biometry, and device-passcode authorisation would require
        // `.devicePasscode` or `.userPresence`, neither of which is requested.
        // So a biometric lockout fails here rather than falling back, which is
        // the point: someone who knows only the device passcode must not reach a
        // wallet the app passcode exists to protect.
        context.localizedFallbackTitle = ""

        let query: [String: Any] = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecUseDataProtectionKeychain): kCFBooleanTrue as Any,
            String(kSecAttrAccount): account,
            String(kSecReturnData): kCFBooleanTrue as Any,
            String(kSecMatchLimit): String(kSecMatchLimitOne),
            String(kSecUseAuthenticationContext): context
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw BiometricUnlockError.failed }
            return data
        case errSecUserCanceled:
            throw BiometricUnlockError.cancelled
        case errSecItemNotFound:
            throw BiometricUnlockError.notEnabled
        default:
            // Everything else — lockout, changed enrolment, no hardware — is a
            // failure that sends the user to the passcode.
            throw BiometricUnlockError.failed
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecUseDataProtectionKeychain): kCFBooleanTrue as Any,
            String(kSecAttrAccount): account
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricUnlockError.storageFailed
        }
    }

    func exists(account: String) -> Bool {
        // Presence must be checkable without prompting for a face every time a
        // settings screen appears — but **not** by skipping the item, which is
        // what asking for it used to do.
        //
        // `kSecUseAuthenticationUISkip` does what it says: it *silently skips*
        // every item that requires authentication. Ours requires exactly that,
        // so the search excluded it and answered `errSecItemNotFound` — and this
        // returned `false` for a copy that was sitting right there. Enabling the
        // shortcut on a real device therefore stored the key, threw nothing, and
        // then reported itself off; the switch snapped back with no error to
        // show. The old `errSecInteractionNotAllowed` branch was describing a
        // different flag's behaviour and could never be reached.
        //
        // Two things now keep it from prompting. The query asks for *attributes*
        // and never the data — the access control guards the secret, not the
        // fact that a row exists — and the context refuses interaction outright
        // if some OS version decides otherwise. A refusal still answers the
        // question: an item that declined to authenticate is an item that is
        // there.
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecUseDataProtectionKeychain): kCFBooleanTrue as Any,
            String(kSecAttrAccount): account,
            String(kSecReturnAttributes): kCFBooleanTrue as Any,
            String(kSecMatchLimit): String(kSecMatchLimitOne),
            String(kSecUseAuthenticationContext): context
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess, errSecInteractionNotAllowed:
            return true
        case errSecItemNotFound:
            return false
        default:
            // Neither present nor confirmed absent. Answering `false` is the
            // safe direction — it under-reports the shortcut rather than
            // claiming one exists — but it is a guess, and the last time this
            // function guessed it cost a device-only bug that no test could see.
            logger.error("Biometric data key presence check failed: \(status, privacy: .public)")
            return false
        }
    }
}
