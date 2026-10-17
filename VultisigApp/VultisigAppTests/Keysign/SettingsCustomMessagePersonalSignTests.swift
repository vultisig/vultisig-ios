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
