//
//  OnboardingOverviewContentTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class OnboardingOverviewContentTests: XCTestCase {

    private func makeContent(
        tssType: TssType,
        setupType: KeyImportSetupType
    ) -> OnboardingOverviewContent {
        OnboardingOverviewContent(tssType: tssType, setupType: setupType)
    }

    // MARK: - Reshare variant (the redesign's backup guide)

    func testReshareSecureUsesRedesignCopyAndShowsOldBackupsRow() {
        let content = makeContent(tssType: .Reshare, setupType: .secure(numberOfDevices: 2))

        XCTAssertEqual(content.descriptionKey, "backupsDescription")
        XCTAssertNil(content.descriptionHighlightKey)
        XCTAssertEqual(content.backupRowTitleKey, "backupEachDevice")
        XCTAssertEqual(content.backupRowSubtitle, .plain(key: "backupEachDeviceDescription"))
        XCTAssertEqual(content.storeSeparatelyRowSubtitleKey, "storeBackupsSeparatelyDescription")
        XCTAssertTrue(content.showsOldBackupsRow)
        XCTAssertEqual(content.buttonTitleKey, "continue")
    }

    func testReshareFastKeepsDriverRowAndShowsOldBackupsRow() {
        let content = makeContent(tssType: .Reshare, setupType: .fast)

        XCTAssertEqual(content.backupRowTitleKey, "backupDeviceDriver")
        XCTAssertEqual(content.backupRowSubtitle, .plain(key: "backupDeviceDriverDescription"))
        XCTAssertEqual(content.backupRowHighlightKey, "backupDeviceDriverDescriptionHighlight")
        XCTAssertTrue(content.showsOldBackupsRow)
        XCTAssertEqual(content.buttonTitleKey, "continue")
    }

    // MARK: - Existing flows keep their copy

    func testKeygenSecureKeepsExistingCopyAndHidesOldBackupsRow() {
        let content = makeContent(tssType: .Keygen, setupType: .secure(numberOfDevices: 3))

        XCTAssertEqual(content.descriptionKey, "backupsDescriptionVault")
        XCTAssertEqual(content.descriptionHighlightKey, "backupsDescriptionVaultHighlight")
        XCTAssertEqual(content.backupRowTitleKey, "backupEachDevice")
        XCTAssertEqual(
            content.backupRowSubtitle,
            .secureCount(key: "backupEachDeviceDescriptionSecure", count: 3)
        )
        XCTAssertEqual(content.storeSeparatelyRowSubtitleKey, "storeBackupsSeparatelyDescriptionSecure")
        XCTAssertFalse(content.showsOldBackupsRow)
        XCTAssertEqual(content.buttonTitleKey, "iUnderstand")
    }

    func testKeygenFastKeepsDriverRow() {
        let content = makeContent(tssType: .Keygen, setupType: .fast)

        XCTAssertEqual(content.backupRowTitleKey, "backupDeviceDriver")
        XCTAssertEqual(content.backupRowSubtitle, .plain(key: "backupDeviceDriverDescription"))
        XCTAssertEqual(content.storeSeparatelyRowSubtitleKey, "storeBackupsSeparatelyDescription")
        XCTAssertFalse(content.showsOldBackupsRow)
    }

    func testKeyImportKeepsExistingCopy() {
        let content = makeContent(tssType: .KeyImport, setupType: .fast)

        XCTAssertEqual(content.descriptionKey, "backupsDescription")
        XCTAssertNil(content.descriptionHighlightKey)
        XCTAssertEqual(content.backupRowTitleKey, "backupEachDevice")
        XCTAssertEqual(content.backupRowSubtitle, .plain(key: "backupEachDeviceDescription"))
        XCTAssertEqual(content.storeSeparatelyRowSubtitleKey, "storeBackupsSeparatelyDescription")
        XCTAssertFalse(content.showsOldBackupsRow)
        XCTAssertEqual(content.buttonTitleKey, "continue")
    }
}
