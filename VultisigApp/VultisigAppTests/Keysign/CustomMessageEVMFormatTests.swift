@testable import VultisigApp
import XCTest

final class CustomMessageEVMFormatTests: XCTestCase {

    private func payload(method: String, message: String, chain: String = "Ethereum") -> CustomMessagePayload {
        CustomMessagePayload(method: method, message: message, vaultPublicKeyECDSA: "", vaultLocalPartyID: "", chain: chain)
    }

    func testAcceptsPersonalSignEnvelopeWithASCII() {
        let message = SettingsCustomMessageView.personalSignMessage(for: "Hello Vultisig")
        XCTAssertNoThrow(try payload(method: "personal_sign", message: message).validateEVMSignable())
    }

    func testAcceptsPersonalSignEnvelopeWithMultiByteUTF8() {
        let message = SettingsCustomMessageView.personalSignMessage(for: "h\u{00E9}llo \u{1F44B}")
        XCTAssertNoThrow(try payload(method: "personal_sign", message: message).validateEVMSignable())
    }

    func testAcceptsPersonalSignEnvelopeWhoseMessageStartsWithDigits() {
        let message = SettingsCustomMessageView.personalSignMessage(for: "123")
        XCTAssertNoThrow(try payload(method: "personal_sign", message: message).validateEVMSignable())
    }

    func testAcceptsTypedDataV4() {
        XCTAssertNoThrow(try payload(method: "eth_signTypedData_v4", message: "{}").validateEVMSignable())
    }

    func testRefusesUnknownMethod() {
        XCTAssertThrowsError(try payload(method: "eth_sign", message: "0x" + String(repeating: "ab", count: 32)).validateEVMSignable())
    }

    func testRefusesPersonalSignWithoutEnvelope() {
        XCTAssertThrowsError(try payload(method: "personal_sign", message: "Hello").validateEVMSignable())
    }

    func testRefusesEnvelopeWithWrongLength() {
        let message = "\u{19}Ethereum Signed Message:\n5Hello Vultisig"
        XCTAssertThrowsError(try payload(method: "personal_sign", message: message).validateEVMSignable())
    }

    func testUnknownChainFallsBackToEthereum() {
        XCTAssertThrowsError(try payload(method: "foo", message: "x", chain: "NoSuchChain").validateEVMSignable())
    }

    func testNonEVMChainUntouched() {
        XCTAssertNoThrow(try payload(method: "sign_message", message: "x", chain: "Solana").validateEVMSignable())
    }
}
