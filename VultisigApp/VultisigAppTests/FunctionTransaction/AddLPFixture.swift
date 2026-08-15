//
//  AddLPFixture.swift
//  VultisigAppTests
//
//  Coins, pools and inbound-address answers for the Add-LP migration tests.
//
//  The inbound fixture deliberately gives ETH a vault address and a router that
//  are different strings. Every wrong-destination assertion in these suites is
//  "the recipient is the router, not the vault" or the reverse, and neither can
//  fail against a fixture where the two happen to be equal.
//

import BigInt
import Foundation
@testable import VultisigApp

enum AddLPFixture {

    // MARK: - Addresses

    static let ethVault = "0xethinboundvault"
    static let ethRouter = "0xethrouter0000000000000000000000000000000"
    static let btcVault = "bc1qethinboundvaultbtc0000000000000"
    /// The address the RUNE fixture carries — the same one a paired-address
    /// memo is expected to name.
    static let thorAddress = FunctionCallFixture.thorAddress

    // MARK: - Coins

    static func ether(rawBalance: String = "5000000000000000000") -> Coin {
        FunctionCallFixture.makeCoin(
            .ethereum,
            ticker: "ETH",
            decimals: 18,
            isNative: true,
            rawBalance: rawBalance,
            address: "0xsender"
        )
    }

    static func usdc(rawBalance: String = "5000000000") -> Coin {
        let coin = FunctionCallFixture.makeCoin(
            .ethereum,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            rawBalance: rawBalance,
            address: "0xsender"
        )
        coin.contractAddress = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        return coin
    }

    static func bitcoin(rawBalance: String = "100000000") -> Coin {
        FunctionCallFixture.makeBTC(rawBalance: rawBalance)
    }

    static func rune(rawBalance: String = "100000000000") -> Coin {
        FunctionCallFixture.makeRUNE(rawBalance: rawBalance)
    }

    // MARK: - Pools

    static let ethPool = "ETH.ETH"
    static let usdcPool = "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    static let btcPool = "BTC.BTC"

    static func pool(_ asset: String) -> ThorchainPool {
        ThorchainPool(
            asset: asset,
            status: "Available",
            balanceAsset: "1000",
            balanceRune: "1000",
            poolUnits: "1000",
            lpUnits: "1000",
            synthUnits: "0",
            synthSupply: "0",
            pendingInboundAsset: "0",
            pendingInboundRune: "0"
        )
    }

    // MARK: - Inbound addresses

    static func inbound(
        chain: String,
        address: String,
        router: String?,
        halted: Bool = false,
        lpActionsPaused: Bool = false
    ) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: address,
            router: router,
            halted: halted,
            global_trading_paused: false,
            chain_trading_paused: false,
            chain_lp_actions_paused: lpActionsPaused,
            gas_rate: "10",
            gas_rate_units: "gwei",
            dust_threshold: nil,
            outbound_fee: nil,
            outbound_tx_size: nil
        )
    }

    /// Healthy ETH and BTC routes.
    static func healthyInbounds() -> [InboundAddress] {
        [
            inbound(chain: "ETH", address: ethVault, router: ethRouter),
            inbound(chain: "BTC", address: btcVault, router: nil)
        ]
    }

    static let healthyFetch: ThorchainLPDestinationResolver.InboundAddressFetch = { _ in healthyInbounds() }
}
