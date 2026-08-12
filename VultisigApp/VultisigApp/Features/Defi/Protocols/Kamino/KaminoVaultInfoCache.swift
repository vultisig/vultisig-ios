//
//  KaminoVaultInfoCache.swift
//  VultisigApp
//

import Foundation

/// Short-lived store for hydrated `KaminoVaultInfo` values, shared by every
/// `KaminoService`.
///
/// A reference type on purpose. `KaminoService` is a `Sendable` struct built
/// fresh at each call site — the Earn list's view model, the deposit form's and
/// the withdraw form's — so an instance property could never let one of them
/// serve another, and that is exactly what is needed here: the Earn list calls
/// `fetchVaultInfo` for every enabled vault, and moments later the form the user
/// tapped into asks for the same thing. `KaminoRoute.deposit` carries only the
/// descriptor, so the hydration was being thrown away at the navigation
/// boundary. Caching at the service rather than widening the route also covers
/// the withdraw form and a cold entry that never passed through the list.
///
/// **Why the TTL is short.** The hydration carries two live values.
///
/// `lookupTable` is what `KaminoTransactionValidator` pins a built transaction
/// against, so a vault repointed at a new table refuses as
/// `unexpectedLookupTable` — safe, but it keeps refusing for as long as the
/// entry lives. A minute bounds that to a single attempt's worth rather than a
/// spell of them. (Evicting the entry on that specific error would sharpen it
/// further; it is not done here because the failure is raised three layers away
/// in the validator, and a minute already bounds it.)
///
/// `tokensPerShare` converts the user's typed token amount into the shares a
/// withdraw burns, so an entry served here can be up to a minute older than a
/// fresh hydration would have been — on top of however long the form has been
/// open, since it pins one `KaminoVaultInfo` for its whole session.
///
/// What that can and cannot do is worth being exact about, because it is the
/// one place a cached value reaches an amount.
///
/// It cannot over-withdraw. The share count is clamped to `held.maximum`, which
/// comes from the freshly read positions response and never from this value,
/// and a 100% withdraw sends that exact share balance rather than a figure
/// converted back out of the asset. It cannot make the screen disagree with
/// itself either: `makeWithdraw` derives the token summary from the same rate
/// it derived the shares from.
///
/// What it leaves is a difference between the token figure displayed and the
/// tokens the chain pays for those shares. That difference is inherent — the
/// rate at signing is never the rate at execution — and a minute of it is
/// vanishingly small: the rate accrues at the vault's APY, so at 8 % a year a
/// minute moves it by about 1.5 × 10⁻⁵ %, or 0.00015 USDC on a 1,000 USDC
/// withdraw. It also moves in one direction only, upward, so the stale rate
/// buys slightly more shares and the user receives slightly more than the
/// figure they approved, never less.
///
/// One consequence, accepted deliberately: a pull-to-refresh on the Earn list
/// inside the TTL re-reads the user's positions and PnL but reuses the vault's
/// own figures. A 30-day APY and a share rate do not move perceptibly in a
/// minute.
final class KaminoVaultInfoCache: @unchecked Sendable {

    static let shared = KaminoVaultInfoCache()

    static let defaultTTL: TimeInterval = 60

    private let ttl: TimeInterval
    private let storage = ThreadSafeDictionary<String, (data: KaminoVaultInfo, timestamp: Date)>()

    /// - Parameter ttl: injectable so expiry is tested rather than assumed, and
    ///   so a test gets a store that cannot be polluted by another one.
    init(ttl: TimeInterval = KaminoVaultInfoCache.defaultTTL) {
        self.ttl = ttl
    }

    /// The stored hydration for `vaultAddress`, or `nil` when there is none or
    /// it has aged out.
    func value(for vaultAddress: String) -> KaminoVaultInfo? {
        Utils.getCachedData(cacheKey: vaultAddress, cache: storage, timeInSeconds: ttl)
    }

    func store(_ info: KaminoVaultInfo, for vaultAddress: String) {
        storage.set(vaultAddress, (data: info, timestamp: Date()))
    }
}
