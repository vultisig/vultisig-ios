//
//  RippleDestinationTagRequirementTests.swift
//  VultisigAppTests
//
//  Pins the RequireDest classification: XRPL `account_info` responses map
//  to a destination-tag requirement via the AccountRoot lsfRequireDestTag
//  flag (0x00020000), with `actNotFound` (unfunded destination — cannot
//  have the flag) and unrecognized shapes handled explicitly.
//

import XCTest
@testable import VultisigApp

final class RippleDestinationTagRequirementTests: XCTestCase {

    private func classify(_ json: String) throws -> RippleDestinationTagRequirement {
        let response = try JSONDecoder().decode(RippleAccountResponse.self, from: Data(json.utf8))
        return RippleService.classifyDestinationTagRequirement(result: response.result)
    }

    private func accountJSON(flags: Int) -> String {
        """
        {"result":{"account_data":{"Account":"rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh","Balance":"1000000","Flags":\(flags),"LedgerEntryType":"AccountRoot","OwnerCount":0,"Sequence":100},"ledger_current_index":95000000,"status":"success","validated":false}}
        """
    }

    func testFlagsWithLsfRequireDestTagClassifiesRequired() throws {
        // lsfRequireDestTag (0x00020000) set among other AccountRoot flags
        // (lsfDefaultRipple 0x00800000 | lsfDepositAuth 0x01000000).
        let flags = 0x00020000 | 0x00800000 | 0x01000000
        XCTAssertEqual(try classify(accountJSON(flags: flags)), .required)
    }

    func testExactFlagClassifiesRequired() throws {
        XCTAssertEqual(try classify(accountJSON(flags: 0x00020000)), .required)
    }

    func testFlagsWithoutBitClassifiesNotRequired() throws {
        XCTAssertEqual(try classify(accountJSON(flags: 0)), .notRequired)
        XCTAssertEqual(try classify(accountJSON(flags: 0x00800000)), .notRequired)
    }

    func testActNotFoundClassifiesAccountNotFound() throws {
        // An unfunded account has no AccountRoot, so it can't require a tag.
        let json = """
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """
        XCTAssertEqual(try classify(json), .accountNotFound)
    }

    func testOtherRpcErrorClassifiesUnknown() throws {
        let json = """
        {"result":{"error":"invalidParams","error_code":31,"status":"error"}}
        """
        XCTAssertEqual(try classify(json), .unknown)
    }

    func testMissingAccountDataClassifiesUnknown() throws {
        XCTAssertEqual(try classify(#"{"result":{"status":"success"}}"#), .unknown)
        XCTAssertEqual(try classify(#"{"result":null}"#), .unknown)
    }

    func testMissingFlagsFieldClassifiesUnknown() throws {
        // account_data present but no Flags — don't guess.
        let json = """
        {"result":{"account_data":{"Account":"rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh","Balance":"1000000"},"status":"success"}}
        """
        XCTAssertEqual(try classify(json), .unknown)
    }
}
