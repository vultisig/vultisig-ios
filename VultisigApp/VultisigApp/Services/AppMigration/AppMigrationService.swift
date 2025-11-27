//
//  AppMigrationService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/11/2025.
//

import Foundation
import SwiftUI

/// Service responsible for handling app migrations
/// Migrations are executed once per migration version on app launch
/// Uses incremental integer versions (1, 2, 3, etc.) independent of app version
class AppMigrationService {
    @AppStorage("lastMigratedVersion") private var lastMigratedVersion: Int = -1

    /// Performs all necessary migrations
    func performMigrationsIfNeeded() {
        let lastVersion = lastMigratedVersion
        let migrations = getAllMigrations()

        // Get the highest migration version available
        guard let latestMigrationVersion = migrations.map(\.version).max() else {
            print("✅ [Migration] No migrations registered")
            return
        }

        // If already migrated to the latest version, skip
        if lastVersion >= latestMigrationVersion {
            print("✅ [Migration] Already migrated to version \(lastVersion)")
            return
        }

        print("🔄 [Migration] Starting migrations from version \(lastVersion) to \(latestMigrationVersion)")

        // Execute migrations in order
        executeMigrations(from: lastVersion, migrations: migrations)

        print("✅ [Migration] Completed all migrations")
    }

    /// Executes all necessary migrations after the last migrated version
    private func executeMigrations(from lastVersion: Int, migrations: [AppMigration]) {
        // Sort migrations by version
        let sortedMigrations = migrations.sorted { $0.version < $1.version }

        // Execute each migration that hasn't been run yet
        for migration in sortedMigrations where migration.version > lastVersion {
            print("🔄 [Migration] Executing migration #\(migration.version): \(migration.description)")
            do {
                try migration.migrate()
                lastMigratedVersion = migration.version
                print("✅ [Migration] Successfully completed migration #\(migration.version)")
            } catch {
                print("❌ [Migration] Failed migration #\(migration.version): \(error.localizedDescription)")
                // Stop executing further migrations if one fails
                break
            }
        }
    }

    /// Returns all registered migrations in order
    private func getAllMigrations() -> [AppMigration] {
        return [
            THORChainDuplicateTokensMigration()
        ]
    }
}

/// Protocol that all migrations must conform to
protocol AppMigration {
    /// The migration version number (incremental: 1, 2, 3, etc.)
    var version: Int { get }

    /// Description of what this migration does
    var description: String { get }

    /// Performs the migration
    /// - Throws: Error if migration fails
    func migrate() throws
}
