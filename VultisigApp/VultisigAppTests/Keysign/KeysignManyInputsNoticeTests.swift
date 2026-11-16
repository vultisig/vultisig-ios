//
//  KeysignManyInputsNoticeTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class KeysignManyInputsNoticeTests: XCTestCase {

    func testNoticeAppearsFromTenMessagesWithTheCount() {
        let vm = KeysignViewModel()
        vm.status = .KeysignECDSA

        vm.messsageToSign = Array(repeating: "hash", count: 9)
        XCTAssertNil(vm.manyInputsNotice)

        vm.messsageToSign = Array(repeating: "hash", count: 10)
        let notice = vm.manyInputsNotice
        XCTAssertEqual(notice, String(format: "signingManyInputsNotice".localized, 10))
        XCTAssertTrue(notice?.contains("10") == true, "notice must carry the message count")
    }
}
