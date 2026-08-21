//
//  DKLSBannedPartyDetectionTests.swift
//  VultisigAppTests
//
//  godkls returns LIB_ABORT_PROTOCOL_AND_BAN_PARTY_1...10 (100-109) when it
//  aborts a session after catching a co-signer misbehaving. That must abort
//  the keysign with a distinct error, not the generic runtime-error string
//  that other lib_error codes get retried against. See vultisig-ios#5226.
//

@testable import VultisigApp
import godkls
import XCTest

final class DKLSBannedPartyDetectionTests: XCTestCase {

    @MainActor
    private func makeKeysign() -> DKLSKeysign {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        vault.localPartyID = "partyA"
        return DKLSKeysign(
            keysignCommittee: ["partyA", "partyB"],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            messsageToSign: ["deadbeef"],
            vault: vault,
            encryptionKeyHex: "00",
            chainPath: "",
            isInitiateDevice: false,
            publicKeyECDSA: "ECDSAKey"
        )
    }

    @MainActor
    func testBanRangeThrowsMaliciousPartyWithOneBasedIndex() throws {
        let keysign = makeKeysign()
        for rawValue: UInt32 in 100...109 {
            XCTAssertThrowsError(try keysign.checkForBannedParty(godkls.lib_error(rawValue))) { error in
                guard case HelperError.maliciousParty(let partyIndex) = error else {
                    return XCTFail("expected HelperError.maliciousParty, got \(error)")
                }
                XCTAssertEqual(partyIndex, Int(rawValue) - 100 + 1)
            }
        }
    }

    @MainActor
    func testNonBanCodesDoNotThrow() throws {
        let keysign = makeKeysign()
        // LIB_OK, and a selection of ordinary/unrelated lib_error codes,
        // including the neighboring (non-ban) LIB_ABORT_PROTOCOL_PARTY_* range.
        for rawValue: UInt32 in [0, 1, 13, 99, 110, 200, 209] {
            XCTAssertNoThrow(try keysign.checkForBannedParty(godkls.lib_error(rawValue)))
        }
    }
}
