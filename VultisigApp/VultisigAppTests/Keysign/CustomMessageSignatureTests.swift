@testable import VultisigApp
import Tss
import XCTest

@MainActor
final class CustomMessageSignatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(keyType: KeyType) -> KeysignViewModel {
        let vm = KeysignViewModel()
        vm.keysignType = keyType
        return vm
    }

    private func makeTssResponse(r: String, s: String, recoveryID: String = "00") -> TssKeysignResponse {
        let resp = TssKeysignResponse()
        resp.r = r
        resp.s = s
        resp.recoveryID = recoveryID
        return resp
    }

    // MARK: - ECDSA

    func testECDSA_validSignature_returnsRSRecoveryIDHex() {
        let vm = makeVM(keyType: .ECDSA)
        vm.signatures["msg"] = makeTssResponse(r: "aabb", s: "ccdd", recoveryID: "01")

        XCTAssertEqual(vm.customMessageSignature(), "aabbccdd01")
    }

    func testECDSA_emptySignatures_returnsEmpty() {
        let vm = makeVM(keyType: .ECDSA)

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    func testECDSA_invalidRHex_returnsEmpty() {
        let vm = makeVM(keyType: .ECDSA)
        vm.signatures["msg"] = makeTssResponse(r: "gg", s: "ccdd")

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    func testECDSA_invalidSHex_returnsEmpty() {
        let vm = makeVM(keyType: .ECDSA)
        vm.signatures["msg"] = makeTssResponse(r: "aabb", s: "zz")

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    // MARK: - EdDSA

    func testEdDSA_validSignature_returnsReversedRSHex() {
        let vm = makeVM(keyType: .EdDSA)
        // TSS delivers r and s in little-endian; getSignature() reverses each.
        vm.signatures["msg"] = makeTssResponse(r: "0102", s: "0304")

        // reversed(0102) = 0201, reversed(0304) = 0403 → concatenated
        XCTAssertEqual(vm.customMessageSignature(), "02010403")
    }

    func testEdDSA_emptySignatures_returnsEmpty() {
        let vm = makeVM(keyType: .EdDSA)

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    func testEdDSA_invalidRHex_returnsEmpty() {
        let vm = makeVM(keyType: .EdDSA)
        vm.signatures["msg"] = makeTssResponse(r: "zz", s: "0304")

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    func testEdDSA_doesNotAppendRecoveryID() {
        let vm = makeVM(keyType: .EdDSA)
        vm.signatures["msg"] = makeTssResponse(r: "aabb", s: "ccdd", recoveryID: "01")

        let sig = vm.customMessageSignature()
        // EdDSA result is exactly 4 bytes (no recovery ID byte).
        XCTAssertEqual(sig.count, 8)
    }

    // MARK: - MLDSA

    func testMLDSA_validDilithiumSignature_returnsRawHex() {
        let vm = makeVM(keyType: .MLDSA)
        let rawHex = String(repeating: "ab", count: 10)
        vm.dilithiumSignatures["msg"] = DilithiumKeysignResponse(msg: "deadbeef", signature: rawHex)

        XCTAssertEqual(vm.customMessageSignature(), rawHex)
    }

    func testMLDSA_emptyDilithiumSignatures_returnsEmpty() {
        let vm = makeVM(keyType: .MLDSA)

        XCTAssertEqual(vm.customMessageSignature(), "")
    }

    func testMLDSA_doesNotReadFromTssSignatures() {
        let vm = makeVM(keyType: .MLDSA)
        // Populate the TSS signatures dict — MLDSA must ignore it.
        vm.signatures["msg"] = makeTssResponse(r: "aabb", s: "ccdd", recoveryID: "01")

        XCTAssertEqual(vm.customMessageSignature(), "")
    }
}
