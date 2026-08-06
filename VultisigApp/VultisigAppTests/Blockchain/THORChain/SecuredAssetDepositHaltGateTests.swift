//
//  SecuredAssetDepositHaltGateTests.swift
//  VultisigAppTests
//
//  Fund-safety gate for SECURE+ mints (`ThorchainRouterDepositBuilder
//  .resolveInboundDestination`). The gate exists so a mint never signs to an
//  empty or stranded destination, so these tests pin BOTH directions: which
//  inbound states must still block, and which must not.
//
//  The regression they guard: `chain_lp_actions_paused` (THORChain's
//  `PauseLP<CHAIN>` mimir) suspends liquidity-provider add/withdraw only —
//  swaps and every other transaction keep processing — yet it was folded into
//  the deposit gate. THORChain leaves it set on healthy chains for long
//  stretches, which blocked every secured-asset deposit network-wide.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SecuredAssetDepositHaltGateTests: XCTestCase {

    // MARK: - Inbound-state predicates

    func testLPActionsPausedAloneIsNotATradingHalt() {
        XCTAssertFalse(entry(lpActionsPaused: true).isTradingHalted)
    }

    func testHaltedIsATradingHalt() {
        XCTAssertTrue(entry(halted: true).isTradingHalted)
    }

    func testGlobalTradingPausedIsATradingHalt() {
        XCTAssertTrue(entry(globalTradingPaused: true).isTradingHalted)
    }

    func testChainTradingPausedIsATradingHalt() {
        XCTAssertTrue(entry(chainTradingPaused: true).isTradingHalted)
    }

    func testAllFlagsClearIsNotATradingHalt() {
        XCTAssertFalse(entry().isTradingHalted)
    }

    /// MayaChain serves no pause flags at all; nil must read as not-paused so
    /// `halted` stays the only halt signal there.
    func testNilPauseFlagsAreNotATradingHalt() {
        XCTAssertFalse(
            InboundAddress(
                chain: "ZEC",
                address: "t1zec",
                router: nil,
                halted: false,
                global_trading_paused: nil,
                chain_trading_paused: nil,
                chain_lp_actions_paused: nil,
                gas_rate: "20",
                gas_rate_units: "satsperbyte",
                dust_threshold: nil,
                outbound_fee: nil,
                outbound_tx_size: nil
            ).isTradingHalted
        )
    }

    // MARK: - The LP predicate must stay strict

    /// The LP-add path (`FunctionCallAddThorLP`) gates on `isLPActionsHalted`,
    /// which — unlike the deposit gate — MUST keep honouring
    /// `chain_lp_actions_paused`. THORChain rejects an LP add while LP actions
    /// are paused, so relaxing this the way the deposit gate was relaxed would
    /// strand funds.
    func testLPActionsPausedAloneIsAnLPHalt() {
        XCTAssertTrue(entry(lpActionsPaused: true).isLPActionsHalted)
    }

    func testEveryTradingHaltIsAlsoAnLPHalt() {
        XCTAssertTrue(entry(halted: true).isLPActionsHalted)
        XCTAssertTrue(entry(globalTradingPaused: true).isLPActionsHalted)
        XCTAssertTrue(entry(chainTradingPaused: true).isLPActionsHalted)
    }

    func testAllFlagsClearIsNotAnLPHalt() {
        XCTAssertFalse(entry().isLPActionsHalted)
    }

    // MARK: - Deposit destination resolution: allowed

    /// The reported bug: Ethereum is online on every trading flag and only has
    /// LP actions paused, so the mint must resolve the inbound vault.
    func testNativeDepositAllowedWhenOnlyLPActionsPaused() async throws {
        let service = makeService(inboundJSON(chain: "ETH", address: "0xvault", lpActionsPaused: true))
        let destination = try await ThorchainRouterDepositBuilder.resolveInboundDestination(
            coin: nativeETH(),
            thorchainService: service
        )
        XCTAssertEqual(destination, "0xvault")
    }

    /// The ERC20 mint routes through the router, not the vault — and that is
    /// equally unaffected by an LP-actions pause.
    func testERC20DepositResolvesRouterWhenOnlyLPActionsPaused() async throws {
        let service = makeService(
            inboundJSON(chain: "ETH", address: "0xvault", router: "0xrouter", lpActionsPaused: true)
        )
        let destination = try await ThorchainRouterDepositBuilder.resolveInboundDestination(
            coin: erc20USDC(),
            thorchainService: service
        )
        XCTAssertEqual(destination, "0xrouter")
    }

    /// A RUNE-source mint is a THORChain-native deposit: no inbound to resolve,
    /// so no inbound state can block it.
    func testThorchainSourceResolvesToOwnAddressWithoutFetchingInbound() async throws {
        let service = makeService("[]")
        let rune = FunctionCallFixture.makeRUNE()
        let destination = try await ThorchainRouterDepositBuilder.resolveInboundDestination(
            coin: rune,
            thorchainService: service
        )
        XCTAssertEqual(destination, rune.address)
    }

    // MARK: - Deposit destination resolution: still blocked

    func testDepositBlockedWhenChainHalted() async {
        await assertBlocked(
            json: inboundJSON(chain: "ETH", address: "0xvault", halted: true, lpActionsPaused: true),
            coin: nativeETH(),
            expected: String(format: "inboundPaused".localized, "ETH")
        )
    }

    func testDepositBlockedWhenGlobalTradingPaused() async {
        await assertBlocked(
            json: inboundJSON(chain: "ETH", address: "0xvault", globalTradingPaused: true),
            coin: nativeETH(),
            expected: String(format: "inboundPaused".localized, "ETH")
        )
    }

    func testDepositBlockedWhenChainTradingPaused() async {
        await assertBlocked(
            json: inboundJSON(chain: "ETH", address: "0xvault", chainTradingPaused: true),
            coin: nativeETH(),
            expected: String(format: "inboundPaused".localized, "ETH")
        )
    }

    func testDepositBlockedWhenInboundMissing() async {
        await assertBlocked(
            json: inboundJSON(chain: "BTC", address: "bc1vault"),
            coin: nativeETH(),
            expected: String(format: "inboundAddressNotFound".localized, "ETH")
        )
    }

    /// A transport/decode failure yields an empty list, which must read as
    /// "no inbound" and block — never as "nothing is halted".
    func testDepositBlockedWhenInboundFetchFails() async {
        await assertBlocked(
            json: "not json",
            coin: nativeETH(),
            expected: String(format: "inboundAddressNotFound".localized, "ETH")
        )
    }

    func testERC20DepositBlockedWhenRouterAbsent() async {
        await assertBlocked(
            json: inboundJSON(chain: "ETH", address: "0xvault", lpActionsPaused: true),
            coin: erc20USDC(),
            expected: String(format: "routerNotAvailable".localized, "ETH")
        )
    }

    func testERC20DepositBlockedWhenRouterEmpty() async {
        await assertBlocked(
            json: inboundJSON(chain: "ETH", address: "0xvault", router: "", lpActionsPaused: true),
            coin: erc20USDC(),
            expected: String(format: "routerNotAvailable".localized, "ETH")
        )
    }

    // MARK: - Live-shape regression

    /// The verbatim shape THORChain served on 2026-08-05: every chain carried
    /// `chain_lp_actions_paused: true`, while only BASE/BSC/SOL were genuinely
    /// halted. ETH must deposit; BSC must not.
    func testLiveInboundSnapshotAllowsEthereumAndBlocksHaltedChain() async throws {
        let snapshot = """
        [
          {"chain":"ETH","address":"0xethvault","router":"0xethrouter","halted":false,
           "global_trading_paused":false,"chain_trading_paused":false,
           "chain_lp_actions_paused":true,"gas_rate":"1","gas_rate_units":"gwei"},
          {"chain":"BSC","address":"0xbscvault","router":"0xbscrouter","halted":true,
           "global_trading_paused":false,"chain_trading_paused":true,
           "chain_lp_actions_paused":true,"gas_rate":"1","gas_rate_units":"gwei"}
        ]
        """
        let destination = try await ThorchainRouterDepositBuilder.resolveInboundDestination(
            coin: nativeETH(),
            thorchainService: makeService(snapshot)
        )
        XCTAssertEqual(destination, "0xethvault")

        await assertBlocked(
            json: snapshot,
            coin: FunctionCallFixture.makeCoin(.bscChain, ticker: "BNB", decimals: 18, isNative: true),
            expected: String(format: "inboundPaused".localized, "BSC")
        )
    }

    // MARK: - Helpers

    private func assertBlocked(
        json: String,
        coin: Coin,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let destination = try await ThorchainRouterDepositBuilder.resolveInboundDestination(
                coin: coin,
                thorchainService: makeService(json)
            )
            XCTFail("Expected the deposit to be blocked, resolved \(destination) instead", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, expected, file: file, line: line)
        }
    }

    private func makeService(_ json: String) -> ThorchainService {
        ThorchainService(
            httpClient: InboundStubClient(inboundBody: Data(json.utf8))
        )
    }

    private func nativeETH() -> Coin {
        FunctionCallFixture.makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
    }

    private func erc20USDC() -> Coin {
        FunctionCallFixture.makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
    }

    private func entry(
        halted: Bool = false,
        globalTradingPaused: Bool = false,
        chainTradingPaused: Bool = false,
        lpActionsPaused: Bool = false
    ) -> InboundAddress {
        InboundAddress(
            chain: "ETH",
            address: "0xvault",
            router: "0xrouter",
            halted: halted,
            global_trading_paused: globalTradingPaused,
            chain_trading_paused: chainTradingPaused,
            chain_lp_actions_paused: lpActionsPaused,
            gas_rate: "1",
            gas_rate_units: "gwei",
            dust_threshold: nil,
            outbound_fee: nil,
            outbound_tx_size: nil
        )
    }

    private func inboundJSON(
        chain: String,
        address: String,
        router: String? = nil,
        halted: Bool = false,
        globalTradingPaused: Bool = false,
        chainTradingPaused: Bool = false,
        lpActionsPaused: Bool = false
    ) -> String {
        let routerField = router.map { "\"router\":\"\($0)\"," } ?? ""
        return """
        [{"chain":"\(chain)","address":"\(address)",\(routerField)"halted":\(halted),
          "global_trading_paused":\(globalTradingPaused),
          "chain_trading_paused":\(chainTradingPaused),
          "chain_lp_actions_paused":\(lpActionsPaused),
          "gas_rate":"1","gas_rate_units":"gwei"}]
        """
    }
}

/// Serves one canned body on `/thorchain/inbound_addresses` and 501s everything
/// else, so a test that accidentally hits another endpoint fails loudly.
private actor InboundStubClient: HTTPClientProtocol {
    private let inboundBody: Data

    init(inboundBody: Data) {
        self.inboundBody = inboundBody
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        guard target.path == "/thorchain/inbound_addresses" else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw HTTPError.invalidResponse
        }
        return HTTPResponse(data: inboundBody, response: response)
    }
}
