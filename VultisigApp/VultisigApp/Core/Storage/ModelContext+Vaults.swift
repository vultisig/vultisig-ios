//
//  ModelContext+Vaults.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData

private let logger = Log.app.store

extension ModelContext {

    /// Every stored ``Vault``, fetched once.
    ///
    /// The one-shot counterpart to `@Query var vaults: [Vault]`, for the call
    /// sites that only ever read the list from an event handler.
    ///
    /// **Why a fetch rather than a query.** A `@Query` re-evaluates the view that
    /// declares it on *any* store change of *any* `@Model` type — not only the
    /// type it queries — because what re-runs it is the context's save
    /// notification, which carries no type. Declared on a view that wraps a large
    /// subtree, that turns a single model write anywhere in the app into a
    /// re-evaluation of everything below it, and every storage service in this
    /// app ends in a save. Where nothing in a `body` reads the list, that
    /// liveness draws nothing and the invalidation is pure cost.
    ///
    /// A view that *renders* the vault list still wants `@Query`, and the ones
    /// that do keep it: the blast radius of a leaf or a sheet is that screen.
    ///
    /// **Ordering matches an unsorted `@Query`** — neither passes a sort
    /// descriptor, so both take the store's own order. Callers that need a
    /// defined order ask for one (`@Query(sort: \Vault.order)`), and this is not
    /// for them.
    ///
    /// Empty on failure. Use ``fetchVaultsIfAvailable()`` instead wherever "there
    /// are no vaults" and "the store could not be read" have to lead to
    /// different decisions.
    func fetchAllVaults() -> [Vault] {
        fetchVaultsIfAvailable() ?? []
    }

    /// Every stored ``Vault``, or `nil` if the fetch failed.
    ///
    /// The distinction the plain `[Vault]` form cannot make. A `@Query` collapses
    /// it too — its `wrappedValue` is a list either way and the failure only
    /// shows up in `fetchError`, which nothing here consults — so "empty" has
    /// always been able to mean "unreadable". That is fine where both answers
    /// lead to the same place, and not fine where one of them skips a lock.
    func fetchVaultsIfAvailable() -> [Vault]? {
        do {
            return try fetch(FetchDescriptor<Vault>())
        } catch {
            logger.error("Failed to fetch vaults: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
