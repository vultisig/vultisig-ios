//
//  CoinMemoSupportTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class CoinMemoSupportTests: XCTestCase {
    func testNativeEvmCoinSupportsMemo() {
        let coin = makeCoin(chain: .ethereum, isNativeToken: true)

        XCTAssertTrue(coin.supportsMemo)
    }

    func testErc20CoinDoesNotSupportMemo() {
        let coin = makeCoin(chain: .ethereum, isNativeToken: false)

        XCTAssertFalse(coin.supportsMemo)
    }

    func testSuiCoinStillDoesNotSupportMemo() {
        let coin = makeCoin(chain: .sui, isNativeToken: true)

        XCTAssertFalse(coin.supportsMemo)
    }

    func testNativePolkadotCoinDoesNotSupportMemo() {
        let coin = makeCoin(chain: .polkadot, isNativeToken: true)

        XCTAssertFalse(coin.supportsMemo)
    }

    func testNativeBittensorCoinDoesNotSupportMemo() {
        let coin = makeCoin(chain: .bittensor, isNativeToken: true)

        XCTAssertFalse(coin.supportsMemo)
    }

    func testNativeCosmosCoinStillSupportsMemo() {
        let coin = makeCoin(chain: .gaiaChain, isNativeToken: true)

        XCTAssertTrue(coin.supportsMemo)
    }

    private func makeCoin(chain: Chain, isNativeToken: Bool) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: isNativeToken ? chain.ticker : "TOKEN",
                logo: "logo",
                decimals: 18,
                priceProviderId: "price-provider",
                contractAddress: isNativeToken ? "" : "0xcontract",
                isNativeToken: isNativeToken
            ),
            address: "address",
            hexPublicKey: "public-key"
        )
    }
}
