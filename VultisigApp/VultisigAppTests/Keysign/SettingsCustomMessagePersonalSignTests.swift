@testable import VultisigApp
import XCTest

final class SettingsCustomMessagePersonalSignTests: XCTestCase {

    func testPersonalSignMessageUsesEIP191Envelope() {
        let message = "Hello Vultisig"

        XCTAssertEqual(
            SettingsCustomMessageView.personalSignMessage(for: message),
            "\u{19}Ethereum Signed Message:\n14Hello Vultisig"
        )
    }

    func testPersonalSignMessageUsesUTF8ByteLength() {
        let message = "h\u{00E9}llo \u{1F44B}"

        XCTAssertEqual(
            SettingsCustomMessageView.personalSignMessage(for: message),
            "\u{19}Ethereum Signed Message:\n11h\u{00E9}llo \u{1F44B}"
        )
    }
}

extension SettingsCustomMessagePersonalSignTests {
    func testPersonalSignHexInputEnvelopesDecodedBytes() {
        let payload = CustomMessagePayload(
            method: "personal_sign",
            message: SettingsCustomMessageView.personalSignMessage(for: "0x6869"),
            vaultPublicKeyECDSA: "",
            vaultLocalPartyID: "",
            chain: "Ethereum"
        )
        let expected = Data("\u{19}Ethereum Signed Message:\n2hi".utf8).sha3(.keccak256).hexString
        XCTAssertEqual(payload.keysignMessages, [expected])
    }
}
