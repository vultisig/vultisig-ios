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

enum BiometricUnlockError: Error, Equatable {
    case notEnabled
    case unavailable
    case cancelled
    case failed
    case storageFailed
}

/// Seam over the biometry-protected Keychain item, so the fail-closed behaviour
/// can be tested without a device and without real Face ID.
protocol BiometricKeychainProtecting {
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
final class BiometricUnlockStore {

    static let shared = BiometricUnlockStore()

    private static let account = "com.vultisig.wallet.biometricDataKey"

    private let keychain: BiometricKeychainProtecting

    init(keychain: BiometricKeychainProtecting = BiometricKeychain()) {
        self.keychain = keychain
    }

    var isEnabled: Bool {
        keychain.exists(account: Self.account)
    }

    /// Stores the data key behind biometry. Requires the caller to already hold
    /// it, i.e. to be unlocked — this never mints or unwraps a key itself.
    func enable(dataKey: SymmetricKey) throws {
        let raw = dataKey.withUnsafeBytes { Data($0) }
        do {
            try keychain.store(raw, account: Self.account)
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

    /// - Returns: the data key, only on a successful biometric match.
    /// - Throws: on every other outcome, so the caller shows the passcode screen.
    func unlock(reason: String) throws -> SymmetricKey {
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

        guard raw.count == VaultCryptoEnvelope.keyLengthBytes else {
            // Present but the wrong shape. Remove it rather than leave a
            // shortcut that cannot work; the passcode still opens the app.
            logger.error("Biometric data key has unexpected length \(raw.count, privacy: .public)")
            try? disable()
            throw BiometricUnlockError.failed
        }

        return SymmetricKey(data: raw)
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
            String(kSecAttrAccount): account,
            String(kSecValueData): data,
            String(kSecAttrAccessControl): access
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricUnlockError.storageFailed
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
            String(kSecAttrAccount): account
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricUnlockError.storageFailed
        }
    }

    func exists(account: String) -> Bool {
        // Deliberately does not read the data: presence must be checkable
        // without prompting for a face every time a settings screen appears.
        let query: [String: Any] = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecAttrAccount): account,
            String(kSecReturnData): kCFBooleanFalse as Any,
            String(kSecUseAuthenticationUI): kSecUseAuthenticationUISkip
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // `interactionNotAllowed` means the item exists but needs authentication,
        // which is exactly the state we are asking about.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
