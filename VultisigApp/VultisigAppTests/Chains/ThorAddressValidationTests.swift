import XCTest
import WalletCore
@testable import VultisigApp

final class ThorAddressValidationTests: XCTestCase {
    func testThorAddressValidationDebug() {
        let addresses = [
            "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w",
            "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey"
        ]

        for address in addresses {
            let serviceResult = AddressService.validateAddress(address: address, chain: .thorChain)
            let bech32Result = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "thor")
            let coinTypeResult = Chain.thorChain.coinType.validate(address: address)

            print("THOR_VALIDATE \(address)")
            print("  AddressService.validateAddress = \(serviceResult)")
            print("  AnyAddress.isValidBech32(hrp: thor) = \(bech32Result)")
            print("  Chain.thorChain.coinType.validate = \(coinTypeResult)")
        }
    }
}
