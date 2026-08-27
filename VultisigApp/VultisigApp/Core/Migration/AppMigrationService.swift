//
//  AppMigrationService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/11/2025.
//

import Foundation
import OSLog

/// Service responsible for handling app migrations
/// Migrations are executed once per migration version on app launch
/// Uses incremental integer versions (1, 2, 3, etc.) independent of app version
///
/// Migration version is stored in Keychain (not UserDefaults) to:
/// 1. Persist across app reinstalls - prevents re-running migrations for existing users
/// 2. Detect fresh installations - new devices have no Keychain entry, so migrations are skipped
struct AppMigrationService {
    private let logger = Log.app.service
    private let keychainService: KeychainService

    init(keychainService: KeychainService = DefaultKeychainService.shared) {
        self.keychainService = keychainService
    }

    /// Performs all necessary migrations
    func performMigrationsIfNeeded() {
        let migrations = getAllMigrations()

        // Get the highest migration version available
        guard let latestMigrationVersion = migrations.map(\.version).max() else {
            logger.info("✅ [Migration] No migrations registered")
            return
        }

        let lastVersion = lastMigratedVersion()

        // If already migrated to the latest version, skip
        if lastVersion >= latestMigrationVersion {
            logger.info("✅ [Migration] Already migrated to version \(lastVersion)")
            return
        }

        logger.info("🔄 [Migration] Starting migrations from version \(lastVersion) to \(latestMigrationVersion)")

        // Execute migrations in order
        executeMigrations(from: lastVersion, migrations: migrations)

        logger.info("✅ [Migration] Completed all migrations")
    }

    /// The version below every registered migration, so that all of them are eligible.
    private static let noVersionRecorded = -1

    /// The last recorded migration version, or ``noVersionRecorded`` when there
    /// is none to be had.
    ///
    /// A stored version cannot say whether this is a fresh install or an update
    /// from a build that predates this service, so an absent record has always
    /// meant "run everything" and the migrations are written to be idempotent.
    /// An unreadable Keychain is folded into the same answer deliberately: the
    /// cost is repeating idempotent work, whereas skipping migrations on a
    /// transient read failure would leave the store half-converted. Nothing here
    /// writes a secret, so `unavailable` carries no risk of overwriting one.
    private func lastMigratedVersion() -> Int {
        switch keychainService.getLastMigratedVersion() {
        case .present(let version):
            return version
        case .absent:
            return Self.noVersionRecorded
        case .unavailable(let status):
            logger.error("⚠️ [Migration] Could not read the last migrated version (status \(status, privacy: .public)) - re-running the idempotent migrations")
            return Self.noVersionRecorded
        }
    }

    /// Executes all necessary migrations after the last migrated version
    private func executeMigrations(from lastVersion: Int, migrations: [AppMigration]) {
        // Sort migrations by version
        let sortedMigrations = migrations.sorted { $0.version < $1.version }

        // Execute each migration that hasn't been run yet
        for migration in sortedMigrations where migration.version > lastVersion {
            logger.info("🔄 [Migration] Executing migration #\(migration.version): \(migration.description, privacy: .public)")
            do {
                try migration.migrate()
                keychainService.setLastMigratedVersion(migration.version)
                logger.info("✅ [Migration] Successfully completed migration #\(migration.version)")
            } catch {
                logger.error("❌ [Migration] Failed migration #\(migration.version): \(error.localizedDescription, privacy: .public)")
                // Stop executing further migrations if one fails
                break
            }
        }
    }

    /// Returns all registered migrations in order
    private func getAllMigrations() -> [AppMigration] {
        return [
            THORChainDuplicateTokensMigration(),
            TonGramRebrandMigration(),
            PromoBannerDismissalMigration(),
            RujiAutoCompoundPositionMigration(),
            TonGramDefiPositionsMigration(),
            StakePositionCeilingMigration(),
            RemoveKujiraMigration()
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
