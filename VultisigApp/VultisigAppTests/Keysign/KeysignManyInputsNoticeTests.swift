//
//  KeysignManyInputsNoticeTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class KeysignManyInputsNoticeTests: XCTestCase {

    func testNoticeAppearsFromThreeMessagesWithTheCount() {
        let vm = KeysignViewModel()
        vm.status = .KeysignECDSA

        vm.messsageToSign = Array(repeating: "hash", count: 2)
        XCTAssertNil(vm.manyInputsNotice)

        vm.messsageToSign = Array(repeating: "hash", count: 3)
        let notice = vm.manyInputsNotice
        XCTAssertEqual(notice, String(format: "signingManyInputsNotice".localized, 3))
        XCTAssertTrue(notice?.contains("3") == true, "notice must carry the message count")
    }
}
