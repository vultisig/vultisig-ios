//
//  StakePositionCeilingMigration.swift
//  VultisigApp
//

import SwiftData

/// Gives every stake position persisted before the withdrawable amount was
/// required one, so no card can offer Unstake against a row that never said how
/// much could come out.
///
/// The unstake sheet takes its ceiling from `StakePosition.availableToUnstake`.
/// Producers must now state it, but rows already on disk predate that and carry
/// `nil` — and nothing corrects them until a refresh both runs and succeeds. A
/// cached row paints an enabled card immediately, the refresh behind it is not
/// awaited, and a read that fails writes nothing at all, so a user who is
/// offline or hitting a failing endpoint could hold a `nil` row indefinitely
/// while its card invited them into an empty sheet.
///
/// `amount` is the right value to backfill because it is exactly what those rows
/// meant: every producer that existed when they were written treated the
/// position's size as the withdrawable quantity, and the old routing read the
/// same field. This records that reading once, in the data, rather than leaving
/// every future reader to re-derive it — which is the reason the field was made
/// mandatory in the first place.
///
/// Rows written after this are unaffected: they already carry a stated ceiling,
/// and the guard skips them.
struct StakePositionCeilingMigration: @MainActor AppMigration {
    /// Surfaced when the store cannot be read. Throwing leaves the migration
    /// version un-bumped so `AppMigrationService` retries on the next launch
    /// rather than marking the backfill as done with no data.
    private enum MigrationError: Error {
        case missingModelContext
    }

    let version: Int = 5

    let description: String = "Recording how much can be withdrawn from existing stake positions"

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else {
            throw MigrationError.missingModelContext
        }

        let descriptor = FetchDescriptor<StakePosition>()

        for position in try modelContext.fetch(descriptor) where position.availableToUnstake == nil {
            position.availableToUnstake = position.amount
        }

        try Storage.shared.save()
    }
}
