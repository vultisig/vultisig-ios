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
        // TSS delivers r and s as big-endian scalars; getSignature() reverses
        // each into a 32-byte little-endian half. Both halves here are already
        // full width, so only the byte-order reversal applies.
        let r = "0102" + String(repeating: "00", count: 30)
        let s = "0304" + String(repeating: "00", count: 30)
        vm.signatures["msg"] = makeTssResponse(r: r, s: s)

        // reversed(0102·00×30) = 00×30·0201, reversed(0304·00×30) = 00×30·0403
        let expected = String(repeating: "00", count: 30) + "0201"
            + String(repeating: "00", count: 30) + "0403"
        XCTAssertEqual(vm.customMessageSignature(), expected)
    }

    func testEdDSA_shortComponentIsZeroPaddedTo32Bytes() {
        let vm = makeVM(keyType: .EdDSA)
        // A scalar whose big-endian form lost a high-order zero byte (tss-lib
        // emits `bigInt.Bytes()`) must be padded to a full 32-byte half, not
        // reversed short — otherwise the assembled signature is under 64 bytes
        // and fails verification.
        vm.signatures["msg"] = makeTssResponse(r: "0102", s: "0304")

        let sig = vm.customMessageSignature()
        // Two 32-byte halves → 64 bytes → 128 hex chars.
        XCTAssertEqual(sig.count, 128)
        XCTAssertEqual(sig.hasPrefix("0201"), true)
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
        // EdDSA result is R || S (two 32-byte halves = 64 bytes) with no trailing
        // recovery-ID byte — ECDSA would append one.
        XCTAssertEqual(sig.count, 128)
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
