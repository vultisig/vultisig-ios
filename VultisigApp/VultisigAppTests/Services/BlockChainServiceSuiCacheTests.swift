//
//  BlockChainServiceSuiCacheTests.swift
//  VultisigAppTests
//
//  Ensures Sui chain-specific payloads are not reused across send amounts.
//

@testable import VultisigApp
import BigInt
import XCTest

final class BlockChainServiceSuiCacheTests: XCTestCase {
    func testSuiBlockSpecificIsNotCacheableBecauseItEmbedsAmountBoundCoinSelection() {
        XCTAssertFalse(BlockChainService.allowsBlockSpecificCache(for: .sui))
    }

    func testSolanaBlockSpecificRemainsNotCacheableBecauseBlockhashExpires() {
        XCTAssertFalse(BlockChainService.allowsBlockSpecificCache(for: .solana))
    }

    func testSuiFetchSpecificThrowsWhenSelectedTokenObjectsCannotCoverPositiveAmount() async throws {
        let tokenType = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"
        let service = BlockChainService(
            suiGasInfoProvider: StubSuiGasInfoProvider(coins: [
                ["coinType": tokenType, "objectID": "0xtoken", "balance": "100"],
                ["coinType": SuiConstants.nativeCoinType, "objectID": "0xgas", "balance": "5000000"]
            ])
        )
        let coin = Coin(
            asset: CoinMeta(
                chain: .sui,
                ticker: "COIN",
                logo: "coin",
                decimals: 6,
                priceProviderId: "coin",
                contractAddress: tokenType,
                isNativeToken: false
            ),
            address: "0xsender",
            hexPublicKey: ""
        )

        do {
            let specific = try await service.fetchSpecific(
                for: coin,
                action: .transfer,
                sendMaxAmount: false,
                isDeposit: false,
                transactionType: .unspecified,
                gasLimit: nil,
                fromAddress: coin.address,
                toAddress: "0xrecipient",
                memo: nil,
                feeMode: .fast,
                amount: BigInt(200)
            )
            if case .Sui = specific {
                XCTFail("Expected Sui token spendable preflight to throw before returning Sui data")
            } else {
                XCTFail("Expected Sui data path")
            }
        } catch {
            XCTAssertEqual(error as? SuiSpendableCoinError, .tokenSelectionCannotCoverAmount)
        }
    }
}

private struct StubSuiGasInfoProvider: SuiGasInfoProviding {
    let coins: [[String: String]]

    func getGasInfo(coin: Coin) async throws -> (BigInt, [[String: String]]) {
        (BigInt(1), coins)
    }

    func dryRunTransaction(transactionBytes: String) async throws -> (computationCost: BigInt, storageCost: BigInt) {
        (BigInt(1_000), BigInt(1_000))
    }
}
