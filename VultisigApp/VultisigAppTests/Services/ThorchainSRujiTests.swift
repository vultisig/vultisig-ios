//
//  ThorchainSRujiTests.swift
//  VultisigAppTests
//
//  Regression cover for issue #4318. sRUJI's on-chain denom is
//  `x/staking-x/ruji` — PR #3837 had renamed it locally to
//  `x/staking-ruji` (mirroring sTCY, which actually moved on the
//  chain). Vaults that picked up the stale contract address can no
//  longer match the API response and end up with duplicate or
//  zero-balance rows. These tests pin the pieces that, together,
//  prevent the regression from recurring:
//    1. `TokensStore.sruji.contractAddress` matches the on-chain denom.
//    2. `[CosmosBalance].balance(denom:coin:)` returns the balance
//       emitted under the on-chain denom for `TokensStore.sruji`.
//    3. `THORChainTokenMetadataFactory.create(asset:)` maps the
//       on-chain denom to `sRUJI` / `sruji`.
//    4. `HiddenToken.matches(_:)` accepts a hidden entry that was
//       persisted with the stale contract address — so toggling sRUJI
//       off-then-on on an existing vault doesn't reappear as a stale
//       duplicate.
//

import XCTest
@testable import VultisigApp

final class ThorchainSRujiTests: XCTestCase {

    private let onChainDenom = "x/staking-x/ruji"
    private let staleDenom = "x/staking-ruji"

    // MARK: - 1. Source-of-truth pin

    func test_tokensStore_sruji_usesOnChainDenom() {
        XCTAssertEqual(TokensStore.sruji.contractAddress, onChainDenom)
        XCTAssertEqual(TokensStore.sruji.ticker, "sRUJI")
        XCTAssertEqual(TokensStore.sruji.chain, .thorChain)
    }

    // MARK: - 2. Balance lookup against on-chain denom

    func test_cosmosBalances_balance_findsSRujiByOnChainDenom() {
        let balances: [CosmosBalance] = [
            CosmosBalance(denom: "rune", amount: "1000"),
            CosmosBalance(denom: onChainDenom, amount: "8833889972")
        ]

        // `balance(denom:coin:)` is called with the chain's native ticker;
        // the non-native branch keys on the coin's contractAddress.
        let amount = balances.balance(denom: "rune", coin: TokensStore.sruji)

        XCTAssertEqual(amount, "8833889972")
    }

    func test_cosmosBalances_balance_returnsZeroForMissingDenom() {
        let balances: [CosmosBalance] = [
            CosmosBalance(denom: "rune", amount: "1000")
        ]

        let amount = balances.balance(denom: "rune", coin: TokensStore.sruji)

        XCTAssertEqual(amount, .zero)
    }

    func test_cosmosBalances_balance_ignoresStaleDenom() {
        // The pre-fix code would resolve sRUJI by the renamed denom; assert
        // the lookup now requires the actual on-chain denom and won't
        // accidentally pick up a stale entry.
        let balances: [CosmosBalance] = [
            CosmosBalance(denom: staleDenom, amount: "123456")
        ]

        let amount = balances.balance(denom: "rune", coin: TokensStore.sruji)

        XCTAssertEqual(amount, .zero)
    }

    // MARK: - 3. Denom → metadata mapping

    func test_metadataFactory_mapsOnChainDenomToSRuji() {
        let meta = THORChainTokenMetadataFactory.create(asset: onChainDenom)

        XCTAssertEqual(meta.symbol, "sRUJI")
        XCTAssertEqual(meta.ticker, "sruji")
        XCTAssertEqual(meta.chain, "THOR")
        XCTAssertEqual(meta.decimals, 8)
    }

    // MARK: - 4. Hidden-token matching across the rename

    func test_hiddenToken_matches_staleContractAgainstCurrentSRuji() {
        // A user who had sRUJI hidden before this fix would have it stored
        // with the renamed contract — toggling sRUJI on must still find that
        // hidden entry and unhide it, not produce a duplicate row.
        let stale = HiddenToken(chain: .thorChain, ticker: "sRUJI", contractAddress: staleDenom)

        XCTAssertTrue(stale.matches(TokensStore.sruji))
    }

    func test_hiddenToken_matches_currentContractAgainstCurrentSRuji() {
        let current = HiddenToken(chain: .thorChain, ticker: "sRUJI", contractAddress: onChainDenom)

        XCTAssertTrue(current.matches(TokensStore.sruji))
    }

    // MARK: - 5. On-chain receipt-balance parse (sizes the `liquid.unbond` funds)
    //
    // The `x/staking-x/ruji` bank balance is the vault's sRUJI SHARE count. It is not a
    // display value (the auto-compounding card shows the staking API's liquid size, i.e.
    // those shares valued in RUJI) — it sizes the funds of a `liquid.unbond`, which
    // spends shares. These pin the parse that feeds it.

    func testParseStakingReceiptAmountFindsSRujiByOnChainDenom() throws {
        let json = """
        {
          "balances": [
            { "denom": "rune", "amount": "1000" },
            { "denom": "\(onChainDenom)", "amount": "8833889972" }
          ]
        }
        """
        let amount = try ThorchainService.parseStakingReceiptAmount(
            data: Data(json.utf8),
            denom: TokensStore.sruji.contractAddress
        )

        XCTAssertEqual(amount, Decimal(8_833_889_972))
    }

    func testParseStakingReceiptAmountReturnsZeroWhenDenomAbsent() throws {
        // A successful response with no sRUJI receipt is a genuine zero — the card keeps it
        // (only a request *failure* falls back to the API `bonded` amount).
        let json = """
        { "balances": [ { "denom": "rune", "amount": "1000" } ] }
        """
        let amount = try ThorchainService.parseStakingReceiptAmount(
            data: Data(json.utf8),
            denom: TokensStore.sruji.contractAddress
        )

        XCTAssertEqual(amount, .zero)
    }

    func testParseStakingReceiptAmountIgnoresStaleDenom() throws {
        let json = """
        { "balances": [ { "denom": "\(staleDenom)", "amount": "123456" } ] }
        """
        let amount = try ThorchainService.parseStakingReceiptAmount(
            data: Data(json.utf8),
            denom: TokensStore.sruji.contractAddress
        )

        XCTAssertEqual(amount, .zero)
    }
}
